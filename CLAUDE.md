# Flutter Helpdesk — Padrões de Arquitetura Backend

Stack: Go (Uber FX) + pgx + gorilla/mux (NSF httpx) + PostgreSQL + MinIO + Qdrant + JWT HS256
Backend: `api/` — handlers em `api/internal/handler/`
Migrations: `db/migrations/`

---

## Handler Go — Template Obrigatório

**Todo novo handler HTTP autenticado usa este template — sem exceções:**

```go
// api/internal/handler/<recurso>.go
type TicketsHandler struct {
    logger logx.Logger
    db     *pgxpool.Pool
}

func NewTicketsHandler(logger logx.Logger, db *pgxpool.Pool) *TicketsHandler {
    return &TicketsHandler{logger: logger, db: db}
}

func (h *TicketsHandler) Name() string       { return "list-tickets" }
func (h *TicketsHandler) URL() string        { return "/api/tickets" }
func (h *TicketsHandler) Methods() []string  { return []string{http.MethodGet} }

func (h *TicketsHandler) Metrics(_ context.Context, _ *http.Request) ([]metricx.MetricsTag, error) {
    return []metricx.MetricsTag{metricx.NewLoTag("endpoint", "list-tickets")}, nil
}

func (h *TicketsHandler) Handle(ctx context.Context, r *http.Request, w http.ResponseWriter) error {
    user := middleware.GetUser(ctx)
    if user == nil {
        writeErr(w, http.StatusUnauthorized, "unauthorized")
        return nil
    }
    // lógica aqui — erros de DB:
    // rows, err := h.db.Query(ctx, `SELECT ...`, params)
    // if err != nil { return errInternal(err) }
    w.Header().Set("Content-Type", "application/json")
    return json.NewEncoder(w).Encode(result)
}

func (h *TicketsHandler) ErrorCode(err error) httpx.Failure {
    logErr(h.logger, "list tickets error", err)
    return httpx.Error(500)
}
```

**Registrar em `api/cmd/server/main.go`:**
```go
httpx.ProvideHandler(handler.NewTicketsHandler),
```

---

## Segurança — Regras Críticas

### SQL Injection — query sempre parametrizada
```go
// CORRETO — pgx parametrizado
rows, err := db.Query(ctx, `SELECT * FROM tickets WHERE id = $1`, id)

// ERRADO — nunca concatenar variáveis em SQL
query := "SELECT * FROM tickets WHERE id = '" + id + "'"  // SQL INJECTION
```

### Nunca expor operações destrutivas via HTTP
- Sem endpoints que executem `TRUNCATE`, `DROP`, `DELETE` sem `WHERE` autenticado
- Sem endpoints de seed/fixtures acessíveis via HTTP em produção
- DDL só em migrations (`db/migrations/`)
- Scripts de manutenção: executar fora do servidor HTTP via CLI

### CORS — nunca `*`
```go
// CORRETO — origens da config
allowedOrigins := strings.Split(cfg.CORS.AllowedOrigins, ",")
cors.New(cors.Options{AllowedOrigins: allowedOrigins, ...})

// PROIBIDO:
cors.New(cors.Options{AllowedOrigins: []string{"*"}})
```

### Impersonation — apenas admin
```go
// Middleware (internal/middleware/auth.go) — só aceitar impersonation se IsAdmin
if impID := r.Header.Get("X-Impersonate-User-Id"); impID != "" && claims.IsAdmin {
    userID = impID
}
```

### Nunca vazar detalhes de erro interno
```go
// CORRETO — dentro de Handle(), para erros de DB:
if err != nil {
    return errInternal(err)  // body: {"error":"internal server error"}, causa logada via ErrorCode
}

// CORRETO — dentro de ErrorCode():
func (h *Handler) ErrorCode(err error) httpx.Failure {
    logErr(h.logger, "handler error", err)  // extrai causa via Unwrap(), loga internamente
    return httpx.Error(500)
}

// ERRADO — expõe detalhes internos ao cliente
http.Error(w, err.Error(), 500)
return err  // err raw vaza mensagem de DB para o cliente
```

---

## Performance — Padrões Obrigatórios

### RLS — SET LOCAL app.current_user_id
Todo handler autenticado usa `WithRLS()` antes de qualquer query:

```go
// internal/repository/rls.go
func WithRLS(ctx context.Context, db *pgxpool.Pool, userID string, fn func(pgx.Tx) error) error {
    tx, _ := db.Begin(ctx)
    defer tx.Rollback(ctx)
    // set_config(name, value, is_local=true) is transaction-scoped and accepts $N params.
    // "SET LOCAL app.current_user_id = $1" is NOT valid — PostgreSQL rejects $N in SET commands.
    tx.Exec(ctx, "SELECT pg_catalog.set_config('app.current_user_id', $1, true)", userID)
    if err := fn(tx); err != nil {
        return err
    }
    return tx.Commit(ctx)
}
```

**Regra:** usar `SELECT pg_catalog.set_config('app.current_user_id', $1, true)` — aceita parâmetros posicionais e é transaction-scoped (terceiro argumento `true` = `SET LOCAL`). Nunca usar `SET LOCAL app.current_user_id = $1` — PostgreSQL rejeita parâmetros posicionais em comandos `SET`.

### Queries paralelas com errgroup
```go
import "golang.org/x/sync/errgroup"

g, gCtx := errgroup.WithContext(ctx)
var ticket Ticket
var comments []Comment

g.Go(func() error {
    return h.db.QueryRow(gCtx, `SELECT id, subject FROM tickets WHERE id = $1`, id).Scan(&ticket.ID, &ticket.Subject)
})
g.Go(func() error {
    rows, err := h.db.Query(gCtx, `SELECT id, body FROM ticket_comments WHERE ticket_id = $1`, id)
    // ... scan rows into comments
    return err
})

if err := g.Wait(); err != nil {
    return err
}
```

### Contagem de registros relacionados — derived table JOIN
```go
// CORRETO — derived table (executa uma vez com índice)
LEFT JOIN (
    SELECT ticket_id, COUNT(*)::int AS cnt
    FROM public.ticket_attachments
    GROUP BY ticket_id
) att ON att.ticket_id = t.id

// ERRADO — correlated subquery (executa para cada linha)
(SELECT COUNT(*)::int FROM public.ticket_attachments WHERE ticket_id = t.id)
```

### Cursor pagination — nunca OFFSET
```go
// CORRETO
WHERE (created_at, id) < ($1::timestamptz, $2::uuid)
ORDER BY created_at DESC, id DESC
LIMIT $3

// ERRADO — OFFSET cresce e degrada com o volume
LIMIT 20 OFFSET 200
```

---

## Padrões de Query

### Índices compostos para cursor pagination em `tickets`
Migration `20260401000000_add_tickets_cursor_index.sql` criou:
- `idx_tickets_cursor` em `(created_at DESC, id DESC)`
- `idx_tickets_process_cursor` em `(process_id, created_at DESC, id DESC)`
- `idx_tickets_assignee_cursor` em `(assigned_to, created_at DESC, id DESC)`

Queries de listagem devem usar esses índices — não criar filtros ad-hoc que os bypass.

---

## Helpers de erro — `api/internal/handler/helpers.go`

Três funções utilitárias usadas em **todos** os handlers:

```go
// writeErr — respostas de erro HTTP (4xx): escreve diretamente no ResponseWriter
writeErr(w, http.StatusBadRequest, "mensagem para o cliente")
return nil

// errInternal — erros de DB/infraestrutura dentro de Handle():
// body retornado: {"error":"internal server error"}  (nunca expõe a causa)
return errInternal(err)

// logErr — usado em ErrorCode(): extrai causa via errors.Unwrap() e loga no servidor
func (h *Handler) ErrorCode(err error) httpx.Failure {
    logErr(h.logger, "handler error", err)
    return httpx.Error(500)
}
```

---

## Auth — Cookie httpOnly

```
POST /api/auth/login   → Set-Cookie: helpdesk_token=<jwt>; HttpOnly; SameSite=Strict; Max-Age=86400
POST /api/auth/logout  → Set-Cookie: helpdesk_token=; Max-Age=-1  (limpa o cookie)
```

- `extractToken()` em `middleware/auth.go`: lê cookie primeiro, fallback `Authorization: Bearer`
- Frontend: `credentials: 'include'` em todos os fetch — **sem** token no header ou localStorage
- `AuthContext.tsx`: chama `apiGetMe()` no mount para verificar sessão (401 = não logado, esperado)
- O `401 GET /api/me` no console do browser ao carregar a página é **comportamento correto**

---

## Arquitetura — Dois padrões coexistem

**Handlers de tickets** usam repositório + service (mais complexos, com lógica de negócio e testes):
```
api/internal/repository/  ← interfaces + PgXxxRepository (pgxpool) + mocks
api/internal/service/     ← TicketService (round-robin, SLA, aprovação)
```
Injeção via Fx: `func NewTicketsHandler(logger, repo repository.TicketRepository, svc *service.TicketService)`

**Demais handlers** (forms, lookup_tables, automations, etc.) injetam `*pgxpool.Pool` diretamente — sem camada de repositório. É o padrão mais simples e correto para CRUDs sem lógica de negócio complexa.

> Não criar repositórios para handlers simples. Usar `*pgxpool.Pool` direto até que a complexidade justifique.

### Armadilha — mapeamento manual de request para service.Input

O `CreateTicketHandler` usa um `createTicketRequest` intermediário que é mapeado manualmente para `service.CreateTicketInput`. Ao adicionar campos novos ao contrato do endpoint, ambos os structs precisam ser atualizados **e** o mapeamento em `Handle()` precisa incluir o novo campo. Omitir o mapeamento faz o campo ser descartado silenciosamente sem erro de compilação.

```go
// createTicketRequest — struct do handler (deserialização JSON)
type createTicketRequest struct {
    ...
    PriorityLevelID *string `json:"priority_level_id"`  // campo do SLA Modelo B
}

// Mapeamento manual em Handle() — NÃO esquecer ao adicionar campos:
t, err := h.svc.Create(ctx, user.ID, service.CreateTicketInput{
    ...
    PriorityLevelID: req.PriorityLevelID,  // se omitido, campo é descartado
})
```

### Armadilha — SSE condicional no storage.Client

`api/internal/storage/minio.go` define o campo `useSSE bool` no `Client`, inicializado como `sc.Endpoint == ""`. Isso distingue AWS S3 (sem endpoint customizado) de MinIO local (com endpoint customizado).

```go
// storage/minio.go
useSSE: sc.Endpoint == "", // MinIO sets a custom endpoint; AWS S3 does not
```

`PresignPut` e `Put` só incluem `ServerSideEncryption: AES256` quando `c.useSSE == true`. Aplicar SSE no MinIO local retorna `501 Not Implemented`. O frontend espelha essa lógica: o header `x-amz-server-side-encryption` só é enviado no PUT se o presigned URL listar esse header em `X-Amz-SignedHeaders` (detecção automática via `src/pages/TicketDetail.tsx`).

**Regra:** nunca aplicar SSE incondicionalmente ao `PresignPut` ou `Put` — sempre verificar `c.useSSE`.

---

## Migrations

- Arquivo: `db/migrations/YYYYMMDD000000_descricao.sql`
- Aplicar localmente: `cd api && make migrate-up`
- `make migrate-up` usa `public._migrations` para tracking — é idempotente (SKIP/APPLY)
- `make migrate-down` faz DROP SCHEMA — **destrutivo, use só em dev**
- Não criar migrations com `TRUNCATE` ou `DELETE FROM` sem `WHERE`
- Migrations destrutivas/obsoletas → mover para `db/migrations/_deprecated/`

---

## Checklist — Novo Handler Go

1. Criar `api/internal/handler/<recurso>.go` com struct + `NewXxx()` + `Name()` + `URL()` + `Methods()` + `Metrics()` + `Handle()` + `ErrorCode()`
2. Registrar em `api/cmd/server/main.go` com `httpx.ProvideHandler(handler.NewXxx)`
3. Queries parametrizadas (`$1`, `$2`) — nunca concatenação de string
4. Usar `WithRLS()` em todo handler autenticado antes das queries
5. Paginação cursor — nunca OFFSET
6. COUNT via derived table JOIN — nunca subquery correlacionada
7. Queries paralelas independentes com `errgroup`
8. `ErrorCode()`: `logErr(h.logger, "...", err)` — nunca expõe detalhes ao cliente
9. Auth guard obrigatório no início de `Handle()`: `user := middleware.GetUser(ctx); if user == nil { writeErr(w, http.StatusUnauthorized, "unauthorized"); return nil }`
10. Erros de DB: `return errInternal(err)` — nunca `return err` direto
11. Storage keys: validar prefixo (`tickets/`, `avatars/`, `knowledge-base/`) e rejeitar `..` e `/` absoluto

---

## Auditoria de Handler Go

Para verificar se um handler segue os padrões, diga:

> **"Audita o handler `<nome>`"** ou **"Esse handler segue os padrões?"**

### Critérios de auditoria

| # | Critério | Verificar |
|---|---|---|
| S1 | SQL parametrizado | Sem concatenação `+` ou `fmt.Sprintf` em strings SQL |
| S2 | Sem operação destrutiva HTTP | Sem TRUNCATE/DROP/DELETE sem WHERE em endpoint aberto |
| S3 | CORS nunca `*` | `AllowedOrigins` vem da config — sem `"*"` hardcoded |
| S4 | Erros não vazam stack/query | `errInternal(err)` em Handle(); `logErr` em ErrorCode() |
| S5 | Impersonation só admin | `X-Impersonate-User-Id` aceito apenas se `claims.IsAdmin` |
| S6 | Path traversal storage | Key sem `..`, sem `/` inicial; prefixo em allowlist (`tickets/`, `avatars/`, `knowledge-base/`) |
| S7 | IDOR attachments | `s3_key` deve iniciar com `tickets/{ticketID}/` antes de confirmar |
| S8 | SQL JOIN correto | Joins via tabelas junction (ex: `user_roles`); nunca usar colunas inexistentes |
| P1 | RLS via `SET LOCAL` | `WithRLS()` chamado antes das queries em handlers autenticados |
| P2 | COUNT via derived table JOIN | Sem correlated subquery para contagem |
| P3 | Cursor pagination | Sem OFFSET numérico — usa `(created_at, id) < ($1, $2)` |
| P4 | Queries paralelas com errgroup | Queries independentes rodam em paralelo |
| E1 | `ErrorCode()` retorna genérico | `logErr(h.logger, "...", err)` + `httpx.Error(500)` |
| E2 | User extraído via middleware | `middleware.GetUser(ctx)` — checar `== nil` e retornar 401 |

O relatório deve listar: ✅ aprovado / ❌ violação encontrada (com linha) / ⚠️ não aplicável.

---

## MCP Server (Help Me)

Ferramenta de dev local que dá ao LLM acesso direto ao schema do banco e à lista de endpoints, sem precisar colar arquivos manualmente.

### Tools disponíveis
- **`get_db_schema`** — retorna tabelas/colunas/tipos do schema `public`. Usar antes de escrever qualquer SQL.
- **`list_handlers`** — retorna todos os endpoints registrados em `api/cmd/server/main.go`, com URL e método HTTP. Usar antes de criar um novo handler.

### Arquivos
```
api/cmd/mcp-server/main.go       ← entry point (fx.New direto, não StartMCPServer)
api/internal/mcptools/
  get_db_schema.go               ← tool: schema do banco
  list_handlers.go               ← tool: endpoints da API
api/helpme-mcp.sh                ← wrapper: carrega .env, seta CONFIG_PATH e HELPME_API_DIR
api/helpme-mcp                   ← binário (gitignored)
```

### Rebuild após mudanças
```bash
cd api && go build -o helpme-mcp ./cmd/mcp-server/
```

### Configuração (Cursor)
Adicionado em `~/.cursor/mcp.json`. Claude Code CLI usa `~/.claude/mcp.json` (arquivo separado).

### Padrões NSF mcpx — armadilhas conhecidas
- **NÃO usar `mcpx.StartMCPServer`**: conflito FX — duplica `configx.Config[ServerConfig]` (já provido por `mcpx.Module`)
- **Construtores de tool devem retornar a interface**: `NewXxxTool(...) mcpx.ToolHandler[TReq, TResp]`, não `*XxxTool`. FX resolve por tipo exato e não faz cast automático de concrete → interface.
- **`ToolHandler.Handle` não recebe `ctx`**: usar `context.Background()` para calls pgx dentro dos tools
