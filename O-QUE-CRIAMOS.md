# O que criamos — Guia completo para não esquecer

> Este documento explica tudo que foi construído para turbinar o desenvolvimento do Help Me com Claude Code e Cursor AI. Escrito para que qualquer pessoa da equipe entenda o que existe, por que foi criado e como usar.

---

## A ideia central — o problema que resolvíamos

Antes de tudo isso, o desenvolvimento do Help Me funcionava assim:

- O Claude Code (IA que ajuda a programar) não sabia nada sobre os padrões do projeto. Ele sugeria código genérico que às vezes estava errado para o nosso stack.
- Toda vez que você começava uma sessão, precisava explicar de novo: "use pgx, não MySQL", "handlers NSF seguem este template", "nunca use OFFSET"...
- Não havia nenhuma automação para tarefas repetitivas: criar um novo endpoint, criar uma migration, auditar um arquivo para ver se está dentro dos padrões.
- A IA esquecia tudo entre sessões.
- O Cursor AI (outro editor com IA) não sabia nada do projeto e dava sugestões completamente genéricas.

**O que fizemos:** montamos uma "memória permanente" e um conjunto de automações para que tanto o Claude Code quanto o Cursor AI entendam profundamente o projeto, sigam os padrões automaticamente e ofereçam ajuda proativa no momento certo — sem você precisar pedir.

---

## Parte 1 — A fundação: Regras e memória permanente

### O que são "rules" (regras)?

Imagine que toda vez que o Claude Code abre um arquivo `.go`, ele lê automaticamente um manual de como código Go deve ser escrito neste projeto. É exatamente isso que as rules fazem.

Criamos dois conjuntos de regras:

#### Regras globais (`~/.claude/rules/`) — valem para todos os projetos
São instruções que o Claude Code lê em toda sessão, independente do projeto:

| Arquivo | O que ensina |
|---------|-------------|
| `golang/nsf-handler.md` | Como todo endpoint HTTP deve ser estruturado (os 6 métodos obrigatórios, o template completo) |
| `golang/nsf-logx.md` | Como fazer logging corretamente (nunca `fmt.Println`, sempre `logx.Logger`) |
| `golang/nsf-errorx.md` | Como tratar erros sem vazar detalhes internos para o cliente |
| `golang/nsf-mcpx.md` | Como criar tools para o servidor MCP |
| `golang/nsf-jobx.md` | Como criar jobs em background (tarefas assíncronas) |
| `common/sql-safety.md` | SQL sempre parametrizado — nunca concatenação de strings (proteção contra SQL injection) |
| `common/no-offset-pagination.md` | Paginação por cursor, nunca OFFSET (performance) |
| `python/fastapi-handler.md` | Padrões para endpoints FastAPI (Python) |
| `typescript/react-component.md` | Como componentes React devem ser escritos |
| `typescript/typescript-errors.md` | Tratamento de erros no frontend |
| `typescript/react-auth.md` | Autenticação com cookie httpOnly, nunca localStorage |
| `typescript/tanstack-query.md` | Como usar TanStack Query corretamente |

#### Regras do projeto (`.cursor/rules/`) — valem para o Help Me
São instruções que o Cursor AI lê ao trabalhar neste repositório:

| Arquivo | O que cobre |
|---------|-------------|
| `go-handler-standards.mdc` | Padrão completo de handler NSF + 14 critérios de auditoria (S1-S8, P1-P4, E1-E2) |
| `frontend-auth.mdc` | Auth, apiClient, TanStack Query no frontend |
| `nsf-mcpx.mdc` | Como criar tools MCP (com armadilhas conhecidas documentadas) |
| `nsf-jobx.mdc` | Como criar jobs jobx v2 (com config, registro, padrões) |
| `workflow-orchestration.mdc` | **NOVO** — quando oferecer qual agente/comando proativamente |
| `dev-local.mdc` | Setup do ambiente de desenvolvimento local |

**Por que isso importa:** O Cursor AI agora tem o mesmo conhecimento do projeto que o Claude Code. Os dois entendem os padrões NSF, os dois sabem quando oferecer ajuda no momento certo.

---

## Parte 2 — Os agentes: especialistas que trabalham por você

### O que é um "agente"?

É um assistente especializado com um propósito único. Em vez de pedir para o Claude Code fazer tudo, você tem especialistas: um para escrever documentação, um para auditar código, um para criar PRDs (especificações de produto).

#### `prd-writer` — Escrevedor de especificações
**Quando usar:** Quando você tem uma ideia de feature nova e precisa transformar isso em uma especificação técnica estruturada.

**O que faz:**
1. Conversa com você para entender o que quer construir
2. Gera um arquivo `docs/prd-{feature}.md` com requisitos, casos de uso, critérios de aceite
3. Gera um `prd.json` estruturado que o `ralph-loop` consegue ler e implementar automaticamente

**Como acionar:** Fale "quero criar um PRD para X" ou "feature nova: descrição"

---

#### `nsf-auditor` — Auditor de código Go
**Quando usar:** Quando quer verificar se um handler Go segue todos os padrões do projeto antes de fazer PR.

**O que verifica (14 critérios):**
- **S1-S8 (Segurança):** SQL injection, operações destrutivas, CORS, vazamento de erros, impersonation, path traversal, IDOR em anexos, JOINs corretos
- **P1-P4 (Performance):** RLS com SET LOCAL, contagem com derived table JOIN, cursor pagination, queries paralelas com errgroup
- **E1-E2 (Erros):** ErrorCode retorna genérico, user extraído via middleware

**Como acionar:** Fale "audita o handler X" ou "esse handler está ok?"

---

#### `doc-curator` — Curador de documentação
**Quando usar:** Após criar features, migrations ou modificar endpoints — para manter a documentação atualizada automaticamente.

**O que faz:**
1. Lê as mudanças recentes no código
2. Atualiza `docs/architecture.md`, `docs/tabelas-de-apoio.md` e outros docs relevantes
3. Gera changelogs e mantém a documentação sincronizada com o código

**Como acionar:** "atualiza a documentação" ou `doc-curator` após um ralph-loop completar

---

#### `project-initializer` — Wizard de novo projeto
**Quando usar:** Ao iniciar um projeto novo do zero.

**O que faz (7 perguntas):**
1. Nome e propósito do projeto?
2. Stack principal? (Go+NSF / React / Python / Monorepo)
3. Tem banco de dados?
4. Tem features de IA?
5. Tem frontend?
6. Vai usar ralph-loop?
7. Outros agentes relevantes?

Cria a estrutura completa, instala WORKFLOW.md local e configura o CLAUDE.md com os padrões corretos.

---

## Parte 3 — Os commands: automações de teclado

### O que é um "command"?

É uma instrução que você digita no chat com `/nome` e o Claude executa uma tarefa completa, interativa ou não. Como atalhos de teclado, mas para tarefas complexas de desenvolvimento.

#### `/new-nsf-handler` — Cria um handler HTTP novo
**Pergunta:** nome do handler, método (GET/POST/etc), precisa de autenticação?, usa repositório ou pool direto?

**Gera:**
- Arquivo `api/internal/handler/nome.go` completo com todos os 6 métodos
- Adiciona `httpx.ProvideHandler(handler.NewNome)` no `main.go`
- Imports corretos (httpx, logx, metricx, middleware)
- Auth guard se autenticado

**Por que existe:** Sem isso, toda vez que você criava um handler tinha que lembrar de 6 métodos, os imports certos, o padrão de erro, o auth guard... com este command, tudo sai correto na primeira vez.

---

#### `/audit-handler` — Audita um handler
**O que faz:** Pega o handler do arquivo aberto (ou que você especificar) e roda os 14 critérios de auditoria.

**Como usar:** Com o arquivo aberto no editor, fale `/audit-handler` — ou `/audit-handler tickets.go`

---

#### `/new-migration` — Cria uma migration SQL
**Pergunta:** descrição da migration

**Gera:** `db/migrations/YYYYMMDDHHMMSS_descricao-kebab.sql` com o timestamp correto e header padrão

**Por que existe:** O timestamp das migrations é crítico — define a ordem de execução. Este command garante que o timestamp está sempre correto e no formato certo.

---

#### `/new-mcp-tool` — Cria uma tool MCP
**Pergunta:** nome da tool, descrição, campos do request/response

**Gera:** Arquivo em `api/internal/mcptools/` com o template correto + registro no `mcp-server/main.go`

---

#### `/new-job` — Cria um background job
**Pergunta:** nome do job, campos do payload, tipo (cron ou event?)

**Gera:** Arquivo em `api/internal/jobs/` com Payload.Kind() + Handle() + registro no `main.go`

---

## Parte 4 — O MCP Server: a IA vê o banco de dados em tempo real

### O que é um "MCP Server"?

MCP (Model Context Protocol) é uma forma de conectar a IA diretamente a ferramentas e dados do seu projeto. Em vez de você copiar e colar o schema do banco ou a lista de endpoints para a IA entender o contexto, ela consulta diretamente.

### O que construímos

Um servidor MCP separado (`api/cmd/mcp-server/`) com duas ferramentas:

#### `get_db_schema` — "Qual é o schema do banco?"
A IA pode perguntar em tempo real quais tabelas existem, quais colunas cada tabela tem, quais são os tipos de dados, quais são as constraints.

**Antes:** Você precisava colar o schema manualmente ou a IA chutava os nomes das colunas (e errava).
**Depois:** A IA consulta diretamente e sempre escreve SQL correto.

#### `list_handlers` — "Quais endpoints a API tem?"
A IA pode ver todos os endpoints registrados em `main.go` com URL e método HTTP.

**Antes:** A IA não sabia o que já existia e às vezes sugeria criar um endpoint que já existia, ou criava conflitos.
**Depois:** A IA vê todos os endpoints antes de criar qualquer coisa nova.

### Como funciona tecnicamente

O MCP server é um binário Go separado que roda em background:
```bash
# Compilar (só precisa fazer quando mudar o código)
cd api && go build -o helpme-mcp ./cmd/mcp-server/

# O script helpme-mcp.sh carrega as variáveis de ambiente e inicia
```

O Cursor AI e o Claude Code leem a configuração em `~/.cursor/mcp.json` e `~/.claude/mcp.json` e iniciam o servidor automaticamente ao abrir uma sessão.

---

## Parte 5 — Jobs em background: tarefas assíncronas que não travam o servidor

### O que são "background jobs" e por que precisamos deles?

Imagine que o usuário cria um ticket. O servidor precisa:
1. Salvar o ticket no banco (rápido — 10ms)
2. Enviar notificação Slack para o time (pode demorar — depende da internet)
3. Gerar insights de IA para o processo (muito lento — 2-3 segundos)
4. Calcular SLA e alertar se estiver em risco (complexo)

Se fizermos tudo no mesmo request HTTP, o usuário fica esperando 3+ segundos para criar um ticket. Ruim.

A solução: o servidor salva o ticket e responde imediatamente. As tarefas lentas são colocadas numa fila e executadas em background, com retry automático se falharem.

### O que construímos

Usamos `NSF jobx v2` (que usa River + PostgreSQL como backend de fila):

| Job | Tipo | O que faz |
|-----|------|-----------|
| `slack-notification` | Event-driven | Envia notificação Slack quando um ticket é criado/modificado. Substituiu o antigo "goroutine fire-and-forget" (que não tinha retry em caso de falha) |
| `sla-breach-check` | Cron (a cada 5 min) | Verifica todos os tickets abertos com `sla_risk_score >= 80` e envia alerta Slack |
| `ai-insight-generator` | Event-driven | Após criação de ticket, gera insights de IA para o processo e persiste em `process_insights` |
| `email-digest` | Cron (8h da manhã) | Resumo diário de tickets por agente (stub — aguarda integração com provedor de email) |

### Como os jobs são duráveis (e por que isso importa)

Com o sistema antigo (goroutines), se o servidor caísse durante o envio de um Slack, a notificação se perdia. Com River:

- Jobs são **persistidos no banco** antes de executar
- Se falharem, River faz **retry automático** com backoff exponencial
- Há uma **UI admin** em `http://localhost:6789/jobs` para ver filas, jobs com erro, histórico
- Jobs "mortos" (que esgotaram retries) ficam em dead letter queue para análise

### A migration necessária

Para os jobs funcionarem, criamos `db/migrations/20260306010000_add_river_jobs.sql` que instala o schema completo do River no PostgreSQL (tabelas `river_job`, `river_leader`, `river_queue`, etc).

---

## Parte 6 — A orquestração: a IA sabe quando agir

### O problema da IA passiva

A IA só age quando você pede. Mas você nem sempre sabe o que pedir, ou esquece de pedir. Exemplo:
- Você cria um handler e esquece de auditar antes do PR
- Você modifica um endpoint e esquece de atualizar a documentação
- Você está discutindo uma feature e não pensa em criar um PRD primeiro

### A solução: WORKFLOW.md e workflow-orchestration.mdc

Criamos dois arquivos que ensinam Claude Code e Cursor AI a serem **proativos**:

**`~/.claude/WORKFLOW.md`** (para Claude Code)
**`.cursor/rules/workflow-orchestration.mdc`** (para Cursor AI)

Esses arquivos definem gatilhos e ações:

| Se o usuário... | A IA oferece... |
|-----------------|-----------------|
| Cria ou edita um handler `.go` | "Quer auditar antes de seguir?" |
| Menciona "feature nova", "quero implementar X" | Oferecer `prd-writer` |
| Diz "vou fazer um PR" | "Antes do PR, quer rodar audit-handler?" |
| Cria uma migration | "Quer que o doc-curator atualize a documentação?" |
| Discute jobs, SLA, notificações | Lembrar que `/new-job` existe |
| Discute novo endpoint | `/new-nsf-handler` antes de escrever código manual |

**O resultado:** A IA antecipa o que você precisa e oferece no momento certo, sem você precisar lembrar de tudo.

---

## Parte 7 — O que é o NSF e por que ele importa aqui

NSF é o **NSX Service Framework** — o framework interno da NSX que define como todos os serviços da empresa são construídos. É um conjunto de ~32 módulos em Go que padronizam:

- Como endpoints HTTP são criados (`httpx`)
- Como logging funciona (`logx`)
- Como erros são tratados (`errorx`)
- Como jobs em background funcionam (`jobx/v2`)
- Como servidores MCP são construídos (`mcpx`)
- Como configuração é carregada (`configx`)
- Como banco de dados é conectado (`postgresqlx`)

**Por que isso importa:** Todo o nosso tooling (rules, agents, commands) foi construído para respeitar o NSF. Quando você cria um handler com `/new-nsf-handler`, o resultado segue exatamente o contrato do NSF. Quando o nsf-auditor audita um arquivo, ele verifica se o NSF está sendo usado corretamente.

**Regra de ouro:** Só usamos pacotes do NSF ou da NSX. Nunca dependências de terceiros diretas sem passar pelo NSF — se o NSF não suporta algo, a discussão é levar isso para o time NSX adicionar ao framework.

---

## Como tudo se conecta — o fluxo completo de uma feature

Digamos que você quer construir "sistema de aprovação de budget para tickets acima de R$10k":

```
1. Você: "quero criar a feature de aprovação de budget"
   → Claude/Cursor identifica: feature nova → oferece prd-writer

2. prd-writer: conversa, gera docs/prd-aprovacao-budget.md e prd.json
   → Você revisa e aprova

3. ralph-loop: lê prd.json, implementa story by story
   - Story 1: migration para campo budget_required
   → /new-migration cria db/migrations/20260310000000_add-budget-approval.sql

   - Story 2: handler GET /api/approvals
   → /new-nsf-handler gera o scaffold completo
   → audit-handler verifica automaticamente ao terminar

   - Story 3: job background para notificar aprovadores
   → /new-job gera o scaffold do job
   → job registrado em main.go

   - Story 4: tool MCP para ver aprovações pendentes
   → /new-mcp-tool gera o scaffold da tool

4. Claude/Cursor: "ralph completou — quer rodar doc-curator para atualizar a documentação?"
   → doc-curator atualiza docs/architecture.md e docs/tabelas-de-apoio.md

5. Você: "vou fazer o PR"
   → Claude/Cursor: "audit-handler rodou? Quer rodar agora nos handlers modificados?"
   → /audit-handler: todos os 14 critérios — se passar, PR liberado
```

Todo esse fluxo acontece com você apenas descrevendo o que quer. A IA sabe o que fazer em cada etapa.

---

## Onde estão os arquivos

### Globais (valem para todos os projetos)
```
~/.claude/
├── rules/
│   ├── golang/
│   │   ├── nsf-handler.md
│   │   ├── nsf-logx.md
│   │   ├── nsf-errorx.md
│   │   ├── nsf-mcpx.md
│   │   └── nsf-jobx.md
│   ├── common/
│   │   ├── sql-safety.md
│   │   └── no-offset-pagination.md
│   ├── python/
│   │   ├── fastapi-handler.md
│   │   ├── python-logging.md
│   │   ├── python-errors.md
│   │   ├── python-mcpx.md
│   │   └── python-jobs.md
│   └── typescript/
│       ├── react-component.md
│       ├── react-auth.md
│       ├── typescript-errors.md
│       ├── tanstack-query.md
│       ├── typescript-jobs.md
│       └── typescript-mcp.md
├── agents/
│   ├── prd-writer.md
│   ├── doc-curator.md
│   ├── nsf-auditor.md
│   └── project-initializer.md
├── commands/
│   ├── new-nsf-handler.md
│   ├── audit-handler.md
│   ├── new-migration.md
│   ├── new-mcp-tool.md
│   └── new-job.md
└── WORKFLOW.md              ← orquestração global do Claude Code
```

### Específicos do Help Me
```
Helpme - GitHub NSX/
├── .cursor/rules/
│   ├── go-handler-standards.mdc      ← handler NSF + auditoria 14 critérios
│   ├── frontend-auth.mdc             ← auth + apiClient + TanStack Query
│   ├── nsf-mcpx.mdc                  ← MCP tools
│   ├── nsf-jobx.mdc                  ← background jobs
│   ├── workflow-orchestration.mdc    ← orquestração proativa (mirror do WORKFLOW.md)
│   └── dev-local.mdc                 ← setup local
├── CLAUDE.md                         ← padrões do projeto (raiz)
├── api/
│   ├── CLAUDE.md                     ← padrões específicos do backend Go
│   ├── cmd/
│   │   ├── server/main.go            ← HTTP server + jobx providers
│   │   └── mcp-server/main.go        ← MCP server dev tool
│   ├── internal/
│   │   ├── jobs/                     ← 4 background jobs
│   │   └── mcptools/                 ← 2 MCP tools
│   ├── helpme-mcp.sh                 ← wrapper do MCP server
│   └── config/config.yaml            ← inclui nsf.jobx.* config
└── db/migrations/
    └── 20260306010000_add_river_jobs.sql  ← schema River para jobs
```

---

## Comparativo: antes vs depois

| Aspecto | Antes | Depois |
|---------|-------|--------|
| A IA sabia os padrões do projeto? | Não — você precisava explicar toda sessão | Sim — rules carregadas automaticamente |
| Criar um handler novo | ~20 minutos lembrando template, imports, padrões | 2 minutos com `/new-nsf-handler` |
| Auditar um handler | Manual, baseado em memória, propenso a esquecer critérios | `/audit-handler` — 14 critérios verificados automaticamente |
| Notificações Slack | goroutine fire-and-forget — sem retry, sem visibilidade | Job durável — retry automático, UI de monitoramento |
| SLA em risco | Não havia verificação periódica automática | Job cron a cada 5 min, alerta Slack automático |
| Documentação | Atualização manual e esquecida | `doc-curator` sincroniza após mudanças |
| Feature nova | Código direto, sem especificação | PRD primeiro, implementação depois, documentação no final |
| Cursor AI conhecia o projeto? | Não — sugestões genéricas | Sim — mesmas 6 regras do Claude Code |
| A IA oferecia help proativo? | Nunca — só quando você pedia | Sim — gatilhos definidos no WORKFLOW.md |
| Schema do banco para a IA | Você colava manualmente | MCP tool `get_db_schema` — consulta em tempo real |
| Lista de endpoints para a IA | Você colava manualmente | MCP tool `list_handlers` — consulta em tempo real |

---

## Como começar a usar — primeiros passos

### No Claude Code (terminal)

```bash
# Criar um novo handler
/new-nsf-handler

# Auditar um handler existente
/audit-handler profiles.go

# Criar uma migration
/new-migration

# Criar um job
/new-job

# Criar uma MCP tool
/new-mcp-tool
```

### No Cursor AI

O Cursor AI carrega as regras automaticamente. Você simplesmente trabalha normalmente e ele:
- Sugere padrões NSF ao escrever código Go
- Oferece auditar quando edita um handler
- Lembra do `/new-nsf-handler` antes de você escrever código manual

### Compilar o MCP server (necessário uma vez)

```bash
cd "/Users/nsx001181/Projetos/Helpme - GitHub NSX/api"
export GOPRIVATE=github.com/NSXBet/*
go build -o helpme-mcp ./cmd/mcp-server/
```

Depois que compilado, o Claude Code e o Cursor AI iniciam automaticamente via configuração em `~/.cursor/mcp.json`.

### Aplicar a migration dos jobs

```bash
cd "/Users/nsx001181/Projetos/Helpme - GitHub NSX/api"
make migrate-up
```

Isso instala o schema River no banco de dados e habilita os jobs em background.

---

## O que ainda pode evoluir

### MCP Server — mais tools

O MCP server pode ganhar mais tools conforme o projeto cresce:
- `query_tickets` — buscar tickets com filtros para a IA raciocinar sobre dados reais
- `get_sla_status` — ver tickets violando SLA em tempo real
- `get_process_schema` — ver fases, agentes, SLA de um processo específico
- `search_knowledge_base` — busca vetorial na base de conhecimento (Qdrant)

**Quando adicionar:** Sempre que a IA precisar perguntar sobre dados do sistema que você teria que colar manualmente.

### Jobs — email digest e mais

O `email_digest` job existe como stub (esqueleto) mas ainda não envia emails de verdade — aguarda integração com provedor de email (SendGrid ou similar).

### Testes E2E

Um skill `webapp-testing` com Playwright pode ser criado para automatizar o fluxo completo: login → criar ticket → aprovar → verificar notificação.

---

## Dicionário rápido — termos usados neste documento

| Termo | O que é |
|-------|---------|
| **Rule** | Arquivo de instruções que a IA lê automaticamente ao abrir certos tipos de arquivo |
| **Agent** | Assistente especializado com um propósito único (prd-writer, nsf-auditor, etc) |
| **Command/Skill** | Atalho `/nome` que executa uma tarefa complexa interativamente |
| **MCP Server** | Servidor que conecta a IA a dados reais do projeto (banco, endpoints) |
| **Background Job** | Tarefa assíncrona que executa fora do request HTTP (Slack, SLA check, etc) |
| **jobx v2** | Módulo NSF para background jobs, usa River + PostgreSQL como backend |
| **River** | Engine de filas de jobs (equivalente ao Sidekiq do Ruby) — integrada via NSF |
| **NSF** | NSX Service Framework — o framework interno que padroniza todos os serviços NSX |
| **FX / Uber FX** | Sistema de injeção de dependências em Go — conecta todos os módulos |
| **RLS** | Row Level Security — segurança a nível de linha no PostgreSQL, aplicada via `SET LOCAL` |
| **Handler** | Um endpoint HTTP (cada arquivo em `api/internal/handler/` é um handler) |
| **Migration** | Script SQL que modifica o schema do banco de dados (tabelas, colunas, índices) |
| **Cursor pagination** | Paginação por "marcador" em vez de número de página — muito mais rápida em grandes volumes |
| **GOPRIVATE** | Variável que diz ao Go para não tentar baixar pacotes privados da NSX do servidor público |
| **Orquestração** | A capacidade da IA de saber QUANDO oferecer qual ferramenta, sem ser pedida |
| **PRD** | Product Requirements Document — especificação técnica de uma feature antes de implementar |
| **ralph-loop** | Agente que implementa um PRD automaticamente, story by story |
| **doc-curator** | Agente que mantém a documentação sincronizada com o código |

---

## Como recriar tudo isso em um projeto novo

> Esta seção é o guia de bootstrap. Siga na ordem. Ao final, o novo projeto terá o mesmo poder de automação e inteligência contextual que o Help Me tem hoje.

### Pré-condição: o que já existe globalmente (não precisa recriar)

Tudo abaixo já está instalado na máquina e funciona em **qualquer** projeto automaticamente:

```
~/.claude/
├── rules/golang/        ← nsf-handler, nsf-logx, nsf-errorx, nsf-mcpx, nsf-jobx
├── rules/python/        ← fastapi, logging, errors, mcpx, jobs, sql-safety
├── rules/typescript/    ← react-component, react-auth, typescript-errors, tanstack-query, mcp, jobs
├── rules/common/        ← sql-safety, no-offset-pagination
├── agents/              ← prd-writer, nsf-auditor, doc-curator, project-initializer
├── commands/            ← new-nsf-handler, audit-handler, new-migration, new-mcp-tool, new-job
└── WORKFLOW.md          ← orquestração proativa global
```

Esses arquivos nunca precisam ser recriados. Eles já ensinam Claude Code e informam o Cursor AI via rules globais.

---

### Passo 1 — Criar o CLAUDE.md do projeto (obrigatório)

Todo projeto novo precisa de um `CLAUDE.md` na raiz. Ele é o "manual do projeto" que o Claude Code lê a cada sessão.

**Conteúdo mínimo obrigatório:**
```markdown
# NomeDoProjeto — Padrões de Arquitetura

Stack: [descreva o stack aqui]
Backend: [onde está o backend]

## Visão geral
[O que o projeto faz, qual o stack principal]

## Comandos principais
[como rodar, como testar, como aplicar migrations]

## Estrutura do projeto
[árvore de diretórios com comentários]

## Padrões críticos
[regras específicas do projeto que a IA deve seguir]

## Checklist — Novo Handler/Endpoint
[lista de verificação para o tipo de código mais comum]
```

**Atalho:** Abra o Claude Code na raiz do novo projeto e diga:
> "Cria um CLAUDE.md para este projeto. Stack: [descreva seu stack]. É um projeto NSF Go / FastAPI Python / etc."

O `project-initializer` agent pode gerar isso interativamente — fale:
> "inicializa este projeto com CLAUDE.md"

---

### Passo 2 — Criar as Cursor Rules do projeto (obrigatório para Cursor AI)

O Cursor AI precisa de arquivos `.cursor/rules/*.mdc` específicos do projeto. Copie os templates do Help Me e adapte:

```bash
# Na raiz do novo projeto
mkdir -p .cursor/rules

# Copiar templates do Help Me como ponto de partida
cp "/Users/nsx001181/Projetos/Helpme - GitHub NSX/.cursor/rules/workflow-orchestration.mdc" .cursor/rules/
```

**Se o projeto for Go + NSF** (copiar todos):
```bash
HELPME=".cursor/rules"
SOURCE="/Users/nsx001181/Projetos/Helpme - GitHub NSX/.cursor/rules"
cp "$SOURCE/go-handler-standards.mdc" "$HELPME/"
cp "$SOURCE/nsf-mcpx.mdc"            "$HELPME/"
cp "$SOURCE/nsf-jobx.mdc"            "$HELPME/"
cp "$SOURCE/workflow-orchestration.mdc" "$HELPME/"
```

**Se o projeto tiver frontend React** (copiar):
```bash
cp "/Users/nsx001181/Projetos/Helpme - GitHub NSX/.cursor/rules/frontend-auth.mdc" .cursor/rules/
```

**Depois:** edite `workflow-orchestration.mdc` para refletir os agentes e padrões relevantes para o novo projeto (remova o que não se aplica, ajuste os padrões na seção "Padrões do projeto — resumo rápido").

---

### Passo 3 — Se o projeto for Go + NSF: configurar GOPRIVATE

O NSF usa pacotes privados da NSX. Sem isso, `go mod tidy` e `go build` falham com 404.

**No `Makefile` do projeto, adicionar no topo:**
```makefile
export GOPRIVATE := github.com/NSXBet/*
```

**Verificar que o `go.mod` tem o replace correto:**
```
replace github.com/NSXBet/nsf => ../../nsf
```
(ajustar o path relativo conforme onde o repo `nsf` está em relação ao projeto)

---

### Passo 4 — Se o projeto usar background jobs (jobx v2): migration River

```bash
# Copiar a migration do Help Me como template
cp "/Users/nsx001181/Projetos/Helpme - GitHub NSX/db/migrations/20260306010000_add_river_jobs.sql" \
   "db/migrations/$(date +%Y%m%d)000000_add_river_jobs.sql"
```

Adicionar na `config/config.yaml`:
```yaml
nsf:
  jobx:
    database:
      host: env://DB_HOST
      port: env://DB_PORT
      user: env://DB_USER
      password: env://DB_PASSWORD
      schema: env://DB_NAME
      ssl_mode: env://DB_SSLMODE
      min_conns: 2
      max_conns: 10
    ui:
      port: 6789
      path: "/jobs"
      username: "admin"
      password: env://JOBX_UI_PASSWORD
```

Aplicar: `make migrate-up`

---

### Passo 5 — Se o projeto usar MCP Server: criar cmd/mcp-server

Copiar como template o `api/cmd/mcp-server/main.go` e `api/helpme-mcp.sh` do Help Me e adaptar as tools para o novo projeto.

```bash
mkdir -p cmd/mcp-server
cp "/Users/nsx001181/Projetos/Helpme - GitHub NSX/api/cmd/mcp-server/main.go" cmd/mcp-server/
cp "/Users/nsx001181/Projetos/Helpme - GitHub NSX/api/helpme-mcp.sh" .
```

Editar `main.go` para registrar as tools do novo projeto (remover `get_db_schema` e `list_handlers` do Help Me e criar as tools específicas do novo projeto).

Compilar: `go build -o projeto-mcp ./cmd/mcp-server/`

Adicionar entrada em `~/.cursor/mcp.json` e/ou `.mcp.json` na raiz do projeto.

---

### Passo 6 — Configurar MCP no Cursor / Claude Code (se criou servidor MCP)

**Para o Cursor AI** (`~/.cursor/mcp.json`):
```json
{
  "mcpServers": {
    "nome-do-projeto": {
      "command": "/bin/bash",
      "args": ["/caminho/para/projeto/projeto-mcp.sh"]
    }
  }
}
```

**Para Claude Code CLI** (`~/.claude/mcp.json`):
```json
{
  "mcpServers": {
    "nome-do-projeto": {
      "command": "/bin/bash",
      "args": ["/caminho/para/projeto/projeto-mcp.sh"]
    }
  }
}
```

**Para Claude Code Extension no VSCode/Cursor** (`.mcp.json` na raiz do projeto):
```json
{
  "mcpServers": {
    "nome-do-projeto": {
      "command": "/bin/bash",
      "args": ["${workspaceFolder}/projeto-mcp.sh"]
    }
  }
}
```

---

### Checklist de bootstrap — novo projeto NSF Go

```
[ ] CLAUDE.md criado na raiz (Passo 1)
[ ] .cursor/rules/ criada com os .mdc relevantes (Passo 2)
[ ] workflow-orchestration.mdc adaptado para o projeto (Passo 2)
[ ] GOPRIVATE configurado no Makefile (Passo 3)
[ ] go.mod com replace NSF correto (Passo 3)
[ ] Migration River aplicada, se usar jobs (Passo 4)
[ ] nsf.jobx.* na config, se usar jobs (Passo 4)
[ ] cmd/mcp-server criado e compilado, se quiser MCP (Passo 5)
[ ] MCP registrado em ~/.cursor/mcp.json e/ou .mcp.json (Passo 6)
[ ] go build ./cmd/server/... passa sem erro
[ ] make migrate-up passa sem erro
```

---

### Checklist de bootstrap — novo projeto FastAPI Python

```
[ ] CLAUDE.md criado na raiz (Passo 1)
[ ] .cursor/rules/ com workflow-orchestration.mdc adaptado (Passo 2)
[ ] Estrutura: routers/, models/, schemas/, services/, dependencies.py (padrão nsf-handler Python)
[ ] structlog configurado no lifespan (padrão python-logging.md)
[ ] Exception handler global registrado no app (padrão python-errors.md)
[ ] MCP server via fastmcp se necessário (padrão python-mcpx.md)
[ ] ARQ ou Celery configurado se tiver background jobs (padrão python-jobs.md)
```

---

### Atalho total: usar o project-initializer

Em vez de fazer tudo manualmente, você pode usar o agente `project-initializer` que faz as 7 perguntas e configura tudo automaticamente:

```
Abra Claude Code na raiz do novo projeto vazio e diga:
"inicia este projeto" ou "setup do projeto"
```

O project-initializer vai:
1. Perguntar stack, banco, IA, frontend, jobs, agentes desejados
2. Criar a estrutura de diretórios
3. Gerar o CLAUDE.md personalizado
4. Criar o `workflow-orchestration.mdc` adaptado
5. Perguntar se quer iniciar com um PRD

**Importante:** O project-initializer é um agente global (já existe em `~/.claude/agents/`). Funciona em qualquer projeto novo, não só no Help Me.
