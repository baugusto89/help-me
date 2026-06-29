# Help Me — Workflow de Desenvolvimento

Claude é o orquestrador. Aplica estas regras proativamente — sem precisar ser solicitado.

---

## Agentes ativos neste projeto

| Agente | Quando acionar |
|---|---|
| `prd-writer` | Feature nova, "quero implementar X", "PRD de Y" |
| `doc-curator` | Após mudanças em handlers, migrations, features completas |
| `nsf-auditor` | Auditoria profunda de handler Go NSF antes de PR crítico |
| `project-initializer` | Novo serviço ou sub-projeto precisar de estrutura |

## Commands ativos neste projeto

| Command | Quando sugerir |
|---|---|
| `/new-nsf-handler` | Antes de criar qualquer handler Go manualmente |
| `/audit-handler` | Após criar/editar handler, antes de PR |
| `/new-migration` | Antes de criar arquivo SQL de migration manualmente |
| `/new-mcp-tool` | Antes de criar tool mcpx manualmente |
| `/new-job` | Antes de criar job jobx manualmente |

---

## Ciclo de feature

### Feature nova
1. **prd-writer** → gera `docs/prd-{feature}.md` + `prd.json`
2. **ralph-loop** → implementa `prd.json` story by story (um commit por story)
3. **audit-handler** → automaticamente após cada handler Go criado ou modificado
4. **doc-curator** → após ralph completar, atualiza `docs/`

### Handler Go novo ou modificado
1. `/new-nsf-handler` → scaffold completo
2. `/audit-handler` → antes de commitar
3. Só sugerir PR depois que audit passou

### Migration nova
1. `/new-migration` → scaffold com timestamp + padrões
2. **doc-curator** → atualiza `docs/tabelas-de-apoio.md` e `docs/architecture.md`

### MCP tool nova
1. `/new-mcp-tool` → scaffold com padrões NSF mcpx
2. Rebuild: `cd api && go build -o helpme-mcp ./cmd/mcp-server/`

### Quando o MCP deve evoluir
O MCP cresce junto com o projeto. Claude vai proativamente oferecer novas tools quando:
- **Nova entidade/domínio criado** (migration nova com tabela relevante) → sugerir tool de consulta
- **Novo fluxo de negócio implementado** (SLA, jobs, aprovação, etc.) → sugerir tool de status
- **Handler criado que retorna dados ricos** → sugerir tool equivalente no MCP
- **Claude pede dados que não estão disponíveis** → sugerir criar a tool que falta
- **Feature do frontend precisa de debugging** → sugerir tool de inspeção de dados

Regra de ouro: **se Claude precisar perguntar ao usuário sobre dados do sistema, provavelmente falta uma MCP tool**.

---

## Gatilhos ativos

| Gatilho | Oferecer |
|---|---|
| Handler `.go` criado ou editado | `/audit-handler` — "Quer auditar antes de seguir?" |
| ralph-loop marca `<promise>COMPLETE</promise>` | `doc-curator` — "Quer atualizar a documentação agora?" |
| Usuário menciona "feature nova", "quero implementar X", "PRD" | `prd-writer` |
| Migration criada | `doc-curator` para atualizar tabelas-de-apoio.md |
| Nova entidade relevante criada (migration) | Oferecer `/new-mcp-tool` para consultar essa entidade via MCP |
| Claude precisou de dados que não estão em nenhuma tool | Oferecer criar MCP tool — "quer que eu adicione uma tool para isso?" |
| "vou fazer um PR" / "posso criar o PR?" | Verificar se audit-handler rodou; se não: "Antes do PR, quer rodar audit-handler?" |
| Erro de compilação em handler Go | Verificar padrões NSF (nsf-handler.md, nsf-errorx.md) |
| Novo endpoint sendo discutido | `/new-nsf-handler` antes de escrever código manualmente |
| MCP tool sendo discutida | `/new-mcp-tool` antes de escrever código manualmente |

---

## Stack deste projeto

- **Backend**: Go + NSF (httpx, logx, metricx, mcpx) + pgx + PostgreSQL
- **Frontend**: React + TypeScript + Vite + TanStack Query + shadcn/ui
- **Infra local**: Docker Compose (postgres:5433, minio, qdrant)
- **MCP**: `api/helpme-mcp.sh` + binary `api/helpme-mcp`

## Comandos principais

```bash
# Dev
cd api && make dev        # hot reload (air)
cd api && make run        # sem hot reload

# Qualidade
cd api && make format     # gofmt + goimports + gofumpt
cd api && make lint       # golangci-lint
cd api && make unit       # testes unitários
cd api && make test       # testes completos

# Migrations
cd api && make migrate-up
cd api && make migrate-down   # DESTRUTIVO — só em dev

# MCP server
cd api && go build -o helpme-mcp ./cmd/mcp-server/
```
