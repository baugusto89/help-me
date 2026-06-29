<div align="center">

# Help Me — Sistema de Chamados

**Plataforma de helpdesk com Kanban, fluxos de aprovação, IA integrada e notificações via Slack.**

[![Go](https://img.shields.io/badge/Go-1.24+-00ADD8?style=flat&logo=go)](https://golang.org)
[![Node](https://img.shields.io/badge/Node-22+-339933?style=flat&logo=node.js)](https://nodejs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-4169E1?style=flat&logo=postgresql)](https://postgresql.org)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat)](LICENSE)

</div>

---

> *(inserir screenshot da tela principal / fila de chamados aqui)*

---

## O que é

**Help Me** é um sistema de helpdesk interno voltado para times de suporte e operações. Permite que colaboradores abram chamados, que agentes e gestores os acompanhem em quadros Kanban com fases configuráveis, e que fluxos de aprovação sejam executados antes de resoluções críticas. Uma base de conhecimento vetorial alimenta um assistente de IA que auxilia agentes durante o atendimento.

---

## Funcionalidades

### Para Colaboradores
- **Portal de chamados** — abertura de tickets com formulários dinâmicos por tipo de processo
- **Acompanhamento** — histórico de chamados abertos e seu status em tempo real
- **Kanban pessoal** — visão do andamento do chamado por fase

### Para Agentes e Gestores
- **Fila de chamados** — listagem filtrada por processo, status, prioridade e responsável
- **Kanban de atendimento** — movimentação de cards entre fases com arrastar e soltar
- **Aprovações** — fluxo de aprovação integrado ao processo; pendências agrupadas em painel dedicado
- **Notificações Slack** — alertas automáticos em canais configurados por evento (abertura, aprovação, resolução)
- **Assistente de IA** — sugestões e respostas contextualizadas pela base de conhecimento via RAG

### Para Administradores
- **Gestão de usuários** — criação, permissões granulares por papel (admin / gestor / agente / colaborador)
- **Configuração de processos** — formulários, fases Kanban, alertas por tempo de fase e automações
- **Integrações** — Slack e Gmail configuráveis pela interface
- **Storage e base de conhecimento** — upload de documentos indexados vetorialmente (Qdrant + OpenAI)
- **Auditoria** — log imutável de ações do sistema
- **Relatórios** — métricas por processo, SLA e responsável

---

## Stack

| Camada | Tecnologia |
|--------|-----------|
| **Frontend** | React 18 · TypeScript · Vite · TailwindCSS · shadcn/ui · TanStack Query |
| **Backend** | Go 1.24 · gorilla/mux · Fx (DI) · pgx |
| **Banco de dados** | PostgreSQL 17 (pgvector) |
| **Busca vetorial** | Qdrant |
| **Storage** | MinIO (S3-compatible) |
| **Notificações** | Slack SDK |
| **IA** | OpenAI (embeddings + LLM) · Anthropic (opcional) |
| **Infraestrutura local** | Docker Compose |

---

## Arquitetura

```
┌─────────────────────────────────┐
│         Browser (React)         │  :5173
│  Vite · TanStack Query · shadcn │
└────────────────┬────────────────┘
                 │ HTTP (JWT)
┌────────────────▼────────────────┐
│        API Go (gorilla/mux)     │  :8080
│  Fx DI · JWT middleware · pgx   │
└────┬──────────┬────────┬────────┘
     │          │        │
  pg :5433  MinIO :9000  Qdrant :6335
```

**Autenticação:** Okta SSO (OIDC Authorization Code + PKCE). Após login via Okta, o backend emite um JWT interno em cookie `httpOnly`. O middleware Go injeta `*User{ID, Email, IsAdmin, Role, Permissions}` no contexto de cada request. Ver [sso-implementation-overview.md](sso-implementation-overview.md) para detalhes.

**Permissões:** Roles derivadas dos grupos Okta no login. Verificadas no handler via `middleware.GetUser(ctx)`. Ver [docs/roles-and-okta-permissions.md](docs/roles-and-okta-permissions.md).

---

## Screenshots

> *(inserir figura da tela de login aqui)*

> *(inserir figura do Portal do Colaborador — abertura de chamado)*

> *(inserir figura da Fila de Chamados — visão do agente)*

> *(inserir figura do Kanban de Atendimento)*

> *(inserir figura do Detalhe do Chamado com histórico e aprovação)*

> *(inserir figura do Painel de Aprovações Pendentes)*

> *(inserir figura da Configuração de Processos — formulários e fases)*

> *(inserir figura do AI Mission Control)*

---

## Pré-requisitos

Antes de rodar o projeto localmente, instale:

| Ferramenta | Versão mínima | Como instalar |
|-----------|--------------|---------------|
| [Docker Desktop](https://www.docker.com/products/docker-desktop) | 24+ | Site oficial |
| [Go](https://golang.org/dl/) | 1.24 | `brew install go` |
| [Node.js](https://nodejs.org) | 22+ | `brew install node` |
| [psql](https://www.postgresql.org) | 15+ | `brew install postgresql` |

---

## Setup rápido

```bash
# 1. Clone o repositório
git clone git@github.com:NSXBet/flutter_helpdesk.git
cd flutter_helpdesk

# 2. Execute o script de setup
./setup.sh
```

O `setup.sh` faz automaticamente:

1. Verifica os pré-requisitos acima
2. Cria o `.env` a partir do `.env.example` *(pausará para você preencher as chaves)*
3. Sobe os containers Docker (postgres, minio, qdrant)
4. Aplica todas as migrations SQL
5. Compila o binário Go (`api/helpdesk-api`)
6. Instala as dependências do frontend

Para subir tudo de uma vez após o setup:

```bash
./setup.sh --start
```

---

## Rodando manualmente

Após o setup, você pode subir os serviços em terminais separados:

```bash
# Terminal 1 — Backend Go
cd api
set -a && source ../.env && set +a
./helpdesk-api
# → http://localhost:8080
```

```bash
# Terminal 2 — Frontend
npm run dev
# → http://localhost:5173
```

```bash
# Parar os containers quando terminar
docker compose down
```

---

## Variáveis de ambiente

Copie `.env.example` para `.env` e preencha:

| Variável | Obrigatória | Descrição |
|----------|-------------|-----------|
| `JWT_SECRET` | ✅ | Gere com `openssl rand -hex 32` (min 32 chars) |
| `DB_HOST` / `DB_PORT` / `DB_USER` / `DB_PASSWORD` / `DB_NAME` | ✅ | Conexão PostgreSQL |
| `OKTA_ISSUER` | ✅ | URL do authorization server Okta (ex: `https://org.oktapreview.com/oauth2/default`) |
| `OKTA_CLIENT_ID` | ✅ | Client ID da aplicação Okta (OIDC Web) |
| `OKTA_CLIENT_SECRET` | ✅ | Client Secret da aplicação Okta |
| `OKTA_REDIRECT_URL` | ✅ | Callback URL registrada no Okta (ex: `http://localhost:8080/authorization-code/callback`) |
| `OKTA_ADMIN_GROUP` | ✅ | Nome do grupo Okta que confere role admin (ex: `FBRP_HelpMe_Admin`) |
| `OKTA_ORG_URL` | ✅ | URL base da org Okta (ex: `https://org.oktapreview.com`) — usado pela Admin API |
| `OKTA_API_TOKEN` | ✅ | Token SSWS da Okta Admin API — para provisioning de grupos |
| `MINIO_ENDPOINT` / `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` / `MINIO_BUCKET` | ✅ | Credenciais do MinIO |
| `QDRANT_URL` | ✅ | URL do Qdrant (ex: `http://localhost:6335`) |
| `OPENAI_API_KEY` | ✅ | Necessária para embeddings e IA |
| `CORS_ORIGINS` | ✅ | Origens permitidas (ex: `http://localhost:5173`) |
| `ANTHROPIC_API_KEY` | ⬜ | Opcional — habilita Claude como LLM |
| `SLACK_BOT_TOKEN` | ⬜ | Opcional — habilita notificações Slack |

---

## Estrutura do projeto

```
.
├── api/                    # Backend Go
│   ├── cmd/server/         # Entry point (main.go + registro de handlers)
│   ├── internal/
│   │   ├── handler/        # Handlers HTTP (um arquivo por recurso)
│   │   ├── middleware/      # JWT auth, user context
│   │   ├── notification/    # Slack service
│   │   ├── storage/         # MinIO client
│   │   └── ai/             # Embedder, LLM, Qdrant client
│   └── helpdesk-api        # Binário compilado (gerado pelo setup.sh)
│
├── src/                    # Frontend React
│   ├── components/         # Componentes reutilizáveis (shadcn/ui + custom)
│   ├── pages/              # Páginas por rota
│   ├── contexts/           # AuthContext, outros
│   └── lib/                # apiClient, utils
│
├── db/migrations/    # Migrations SQL (aplicadas em ordem)
├── docs/                   # Documentação técnica e de produto
├── docker-compose.yml      # Infraestrutura local
├── setup.sh                # Script de setup automático
└── .env.example            # Template de variáveis de ambiente
```

---

## Migrations

As migrations ficam em `db/migrations/` e são aplicadas em ordem lexicográfica pelo `setup.sh` (ou manualmente via Makefile):

```bash
cd api
make migrate-up    # aplica todas
make migrate-down  # reseta o banco (destrutivo — use com cuidado)
```

Para criar uma nova migration:

```bash
# Nomeie com timestamp para garantir ordem de aplicação
touch db/migrations/$(date +%Y%m%d%H%M%S)_descricao_da_mudanca.sql
```

---

## Documentação

| Documento | Conteúdo |
|-----------|----------|
| [docs/architecture.md](docs/architecture.md) | Padrões de handler Go, auth, banco, frontend |
| [docs/approval-flow.md](docs/approval-flow.md) | Fluxo completo de aprovações |
| [docs/tabelas-de-apoio.md](docs/tabelas-de-apoio.md) | Lookup tables (departamentos, áreas, etc.) |
| [docs/roles-and-okta-permissions.md](docs/roles-and-okta-permissions.md) | Roles, permissões, grupos Okta e auto-provisioning |
| [sso-implementation-overview.md](sso-implementation-overview.md) | Detalhes técnicos do fluxo OIDC + PKCE com Okta |
| [DOCS_INDEX.md](DOCS_INDEX.md) | Índice completo de toda a documentação |

---

## Papéis e permissões

| Papel | Grupo Okta | Acesso |
|-------|-----------|--------|
| `admin` | `FBRP_HelpMe_Admin` | Acesso total — configurações, usuários, processos, storage, IA |
| `gestor` | *(não mapeado ainda)* | Fila, Kanban, aprovações, relatórios de seu processo |
| `agente` | *(não mapeado ainda)* | Fila e Kanban dos chamados que lhe forem atribuídos |
| `colaborador` | `FBRP_HelpMe` | Portal de abertura e acompanhamento dos próprios chamados |

> Roles são sincronizadas do Okta a cada login. Ver [docs/roles-and-okta-permissions.md](docs/roles-and-okta-permissions.md) para detalhes.

---

<div align="center">
  <sub>Help Me — desenvolvido com Go, React e muito café ☕</sub>
</div>
