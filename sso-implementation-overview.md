# SSO Implementation Overview — Email/Password to Okta OIDC

## Summary

This branch replaces the previous email/password authentication (bcrypt + JWT cookie) with **Okta SSO** using the **OIDC Authorization Code flow with PKCE** (Proof Key for Code Exchange, RFC 7636). After Okta validates the user, the backend mints its own internal JWT and sets the same `helpdesk_token` httpOnly cookie — so all existing middleware, `/api/me`, permissions, impersonation, and protected routes continue working unchanged.

---

## What Changed

### Backend (Go)

| File | Action | Description |
|------|--------|-------------|
| `api/internal/handler/okta_login.go` | **Created** | `GET /api/auth/okta` — generates CSRF state + PKCE verifier/challenge, sets cookies, redirects to Okta authorize URL |
| `api/internal/handler/okta_callback.go` | **Created** | `GET /authorization-code/callback` — validates state + PKCE verifier, exchanges code for tokens, verifies ID token, looks up or auto-provisions user, mints internal JWT, sets `helpdesk_token` cookie, redirects to frontend |
| `api/internal/handler/okta_login_test.go` | **Created** | Tests for login handler: PKCE params, verifier/challenge correctness, cookie attributes, uniqueness, Secure flag |
| `api/internal/handler/okta_callback_test.go` | **Created** | Tests for callback handler: state/verifier validation, cookie cleanup, frontend URL resolution, error redirects |
| `api/internal/handler/login.go` | **Deleted** | Old email/password login handler (bcrypt validation) |
| `api/internal/handler/ratelimit.go` | **Deleted** | Rate limiter — was only used by the login handler |
| `api/internal/handler/users.go` | **Modified** | Removed password/bcrypt; admin can now pre-provision users by email + role only |
| `api/internal/handler/logout.go` | **Modified** | Changed `SameSite` from `Strict` to `Lax` to match the session cookie |
| `api/internal/config/config.go` | **Modified** | Added `OktaConfig` struct (issuer, client_id, client_secret, redirect_url) |
| `api/config/config.yaml` | **Modified** | Added `okta:` section under `app:` with `env://` references |
| `api/cmd/server/main.go` | **Modified** | Removed `LoginHandler`, added `OktaLoginHandler` + `OktaCallbackHandler` |
| `api/go.mod` | **Modified** | Added `github.com/coreos/go-oidc/v3` and `golang.org/x/oauth2` |

### Frontend (React/TypeScript)

| File | Action | Description |
|------|--------|-------------|
| `src/contexts/AuthContext.tsx` | **Modified** | Replaced `login(email, password)` with `loginWithOkta()` (redirects to backend `/api/auth/okta`) |
| `src/pages/Auth.tsx` | **Modified** | Removed email/password form; replaced with a single "Entrar com Okta" button |
| `src/pages/AuthCallback.tsx` | **Modified** | On mount, calls `refreshAuth()` to pick up the cookie set by the backend callback redirect |

### Database Migration

| File | Action | Description |
|------|--------|-------------|
| `db/migrations/20260311000000_okta_sso_auth.sql` | **Created** | Adds `okta_sub` column to `auth.users` + unique indexes for OIDC user matching |
| `db/migrations/20260416100000_add_okta_group_id.sql` | **Created** | Adds `okta_group_id` column to `roles` and `okta_provisioning_rules` + backfills known IDs |

---

## Authentication Flow

```
1. User clicks "Entrar com Okta" on the login page
2. Frontend redirects to:  GET /api/auth/okta
3. Backend:
   a. Generates cryptographic CSRF state (32 bytes, base64url)
   b. Generates PKCE code_verifier (oauth2.GenerateVerifier)
   c. Derives code_challenge = base64url(sha256(code_verifier))
   d. Sets okta_state cookie (HttpOnly, Lax, 300s)
   e. Sets okta_verifier cookie (HttpOnly, Lax, 300s)
   f. Redirects to Okta authorize URL with code_challenge + code_challenge_method=S256
4. User authenticates on Okta's login page
5. Okta redirects to: GET /authorization-code/callback?code=...&state=...
6. Backend:
   a. Validates CSRF state against okta_state cookie
   b. Validates okta_verifier cookie is present
   c. Clears both ephemeral cookies
   d. Exchanges authorization code for tokens, sending code_verifier (PKCE proof)
   e. Verifies and parses ID token claims (sub, email, name)
   f. Looks up user by email in auth.users:
      - Found: backfills okta_sub if null
      - Not found: auto-provisions with colaborador role
   g. Checks admin role via user_roles
   h. Mints internal JWT (same as before)
   i. Sets helpdesk_token httpOnly cookie (SameSite=Lax)
   j. Redirects to frontend /auth/callback
7. Frontend AuthCallback picks up session via refreshAuth() -> GET /api/me
8. User is logged in
```

### Why PKCE?

Without PKCE, an attacker who intercepts the authorization code (e.g., via referrer headers, browser history, or shared network) could exchange it for tokens. PKCE binds the code to the original client by requiring proof of a secret (`code_verifier`) that was never sent over the wire — only its SHA-256 hash (`code_challenge`) was included in the initial authorize request. This is recommended by OAuth 2.1 (RFC 9126).

---

## Security Measures

| Measure | Implementation |
|---------|----------------|
| **PKCE (S256)** | `code_verifier` stored in httpOnly cookie; `code_challenge` sent to Okta; `code_verifier` sent on exchange |
| **CSRF state** | 32-byte random state in httpOnly cookie; validated on callback |
| **Cookie security** | All cookies: HttpOnly, SameSite=Lax, Secure auto-detected behind TLS |
| **ID token verification** | Signature + audience verified via OIDC provider discovery |
| **JWT signing validation** | Rejects non-HMAC signing methods; enforces 32-char minimum secret |
| **SQL injection prevention** | All queries use parameterized `$1`, `$2` — no string concatenation |
| **Error handling** | Internal errors never leaked to client; logged server-side only |
| **Impersonation** | Admin-only, validated in middleware |
| **URL encoding** | Authorize URL built with `net/url` — no raw string interpolation |
| **HTTPS enforcement** | `NewService()` panics if `OKTA_ORG_URL` is not `https://` — refuses to send API token over plain HTTP |
| **Input validation** | Email, Okta ID, group name, and search query validated via regex before any API call |
| **Okta group ID integrity** | All group operations prefer the immutable 20-char Okta group ID over the mutable group name |
| **Backend admin enforcement** | All admin endpoints check `user.IsAdmin` (resolved per-request from DB) — collaborators get HTTP 403 |
| **Approver validation** | Ticket creation rejects self-approval and non-admin/gestor approvers at the service layer |

---

## What Stayed the Same

- **Internal JWT** — same HS256 token with `{sub, email}` claims (permissions resolved per-request from DB, not cached in JWT)
- **Auth middleware** — `middleware.GetUser(ctx)` works identically
- **Cookie name** — `helpdesk_token` (httpOnly)
- **`/api/me` endpoint** — session introspection unchanged
- **Impersonation** — admin-only `X-Impersonate-User-Id` header
- **All protected routes** — no changes needed
- **Logout** — `POST /api/auth/logout` clears the cookie as before

---

## Setup — How to Make It Work on Any Machine

### 1. Environment Variables

Create a `.env` file at the project root (it is gitignored) with the following Okta-related variables:

```env
# Okta SSO (required)
OKTA_ISSUER=https://<your-okta-domain>/oauth2/default
OKTA_CLIENT_ID=<your-okta-client-id>
OKTA_CLIENT_SECRET=<your-okta-client-secret>
OKTA_REDIRECT_URL=http://localhost:8080/authorization-code/callback
```

These are added alongside the existing environment variables (DB, JWT, CORS, MinIO, etc.). See the existing `.env.example` or ask a team member for the full template.

### 2. Okta Application Configuration

In your Okta admin dashboard, ensure the application is configured with:

- **Sign-in redirect URI:** `http://localhost:8080/authorization-code/callback`
- **Sign-out redirect URI:** `http://localhost:5174` (or your frontend port)
- **Grant types:** Authorization Code
- **Scopes:** `openid`, `profile`, `email`

### 3. CORS Origins

The first origin in `CORS_ORIGINS` is used as the frontend redirect target after login. Make sure it matches the port your frontend runs on:

```env
CORS_ORIGINS=http://localhost:5174,http://localhost:5173
```

### 4. Database Migration

Apply the new migration to add the `okta_sub` column:

```bash
cd api && make migrate-up
```

### 5. User Provisioning

- **New users:** automatically provisioned on first Okta login with `colaborador` role
- **Existing users:** matched by email; `okta_sub` is backfilled on first SSO login
- **Admin pre-provisioning:** use `POST /api/users` (admin only) with just an email to create users before their first login

### 6. Go Dependencies

The following dependencies were added (already in `go.mod`):

```
github.com/coreos/go-oidc/v3  — OIDC provider discovery and token verification
golang.org/x/oauth2           — OAuth2 authorization code flow + PKCE
```

---

## Tests

Run the SSO-specific tests:

```bash
cd api && go test -v ./internal/handler/ -run "TestOkta"
```

**Login handler tests (8):** redirect URL structure, PKCE params present, verifier cookie attributes, challenge = S256(verifier), state/verifier uniqueness, Secure flag behind TLS.

**Callback handler tests (9):** missing state cookie, state mismatch, missing verifier cookie, empty verifier cookie, empty state, ephemeral cookie cleanup on error, frontend URL resolution, error redirect URL format.

---

## Sensitive Files (NOT committed)

| File | Contains | Action Required |
|------|----------|-----------------|
| `.env` | All environment variables including Okta credentials | Create locally from template; already in `.gitignore` |
| `.okta-creds` | Okta client ID and secret (raw) | Do not commit; already in `.gitignore` |
