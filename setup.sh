#!/usr/bin/env bash
# =============================================================
#  Flutter Helpdesk — Setup local
#  Uso: ./setup.sh [--start]
#    --start  após o build, sobe API + frontend automaticamente
# =============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
API_DIR="$ROOT/api"
BINARY="$API_DIR/helpdesk-api"
START_SERVICES=false

for arg in "$@"; do
  [[ "$arg" == "--start" ]] && START_SERVICES=true
done

# ─── cores ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

ok()   { echo -e "${GREEN}✔${RESET}  $*"; }
info() { echo -e "${CYAN}▸${RESET}  $*"; }
warn() { echo -e "${YELLOW}⚠${RESET}  $*"; }
fail() { echo -e "${RED}✘  $*${RESET}"; exit 1; }
step() { echo -e "\n${BOLD}── $* ──────────────────────────────${RESET}"; }

# ─── 1. pré-requisitos ───────────────────────────────────────
step "1/5  Verificando pré-requisitos"

check() {
  if command -v "$1" &>/dev/null; then
    ok "$1  ($(command -v "$1"))"
  else
    fail "$1 não encontrado. Instale antes de continuar."
  fi
}

check docker
check go
check node
check psql   # para aplicar migrations

docker info &>/dev/null || fail "Docker não está rodando. Inicie o Docker Desktop."

# ─── 2. ambiente (.env) ──────────────────────────────────────
step "2/5  Ambiente"

if [[ ! -f "$ROOT/.env" ]]; then
  info ".env não encontrado — copiando .env.example"
  cp "$ROOT/.env.example" "$ROOT/.env"
  warn "Edite $ROOT/.env e preencha:"
  warn "  JWT_SECRET   → gere com: openssl rand -hex 32"
  warn "  OPENAI_API_KEY (obrigatório para embeddings/IA)"
  warn ""
  read -r -p "  Pressione ENTER após editar o .env (ou Ctrl+C para cancelar)..."
fi

# carrega vars para uso interno (psql, etc.)
set -a; source "$ROOT/.env"; set +a
ok ".env carregado"

# ─── 3. infraestrutura (Docker) ──────────────────────────────
step "3/5  Infraestrutura (Docker Compose)"

info "Subindo containers (postgres, minio, qdrant)..."
docker compose -f "$ROOT/docker-compose.yml" up -d

info "Aguardando postgres ficar healthy..."
for i in $(seq 1 30); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' helpdesk_postgres 2>/dev/null || echo "missing")
  if [[ "$STATUS" == "healthy" ]]; then
    ok "postgres pronto"
    break
  fi
  [[ $i -eq 30 ]] && fail "Timeout esperando postgres. Verifique: docker logs helpdesk_postgres"
  sleep 2
done

# ─── 4. migrations ───────────────────────────────────────────
step "4/5  Migrations"

DB_URL="postgres://${DB_USER:-helpdesk}:${DB_PASSWORD:-helpdesk}@${DB_HOST:-localhost}:${DB_PORT:-5433}/${DB_NAME:-flutter_helpdesk}?sslmode=disable"
MIGRATIONS_DIR="$ROOT/db/migrations"

TOTAL=$(find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" | wc -l | tr -d ' ')
info "Aplicando $TOTAL arquivos de migration..."

find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" | sort | while IFS= read -r f; do
  ERRORS=$(psql "$DB_URL" -f "$f" 2>&1 | grep -E "^psql:.*ERROR|^ERROR" || true)
  if [[ -n "$ERRORS" ]]; then
    warn "$(basename "$f"): $ERRORS"
  else
    echo -e "  ${GREEN}+${RESET} $(basename "$f")"
  fi
done

ok "Migrations concluídas"

# ─── 5. build ────────────────────────────────────────────────
step "5/5  Build"

# — Backend (Go) —
info "Compilando API Go..."
cd "$API_DIR"
go build -o "$BINARY" ./cmd/server
ok "Binary: $BINARY"

# — Frontend (Node) —
info "Instalando dependências do frontend..."
cd "$ROOT"
if command -v bun &>/dev/null; then
  bun install --frozen-lockfile
else
  npm install
fi
ok "Dependências instaladas"

# ─── Resumo ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}══════════════════════════════════════════${RESET}"
echo -e "${GREEN}  Build concluído com sucesso!${RESET}"
echo -e "${BOLD}══════════════════════════════════════════${RESET}"
echo ""
echo -e "  Para subir os serviços manualmente:"
echo -e "  ${CYAN}# Terminal 1 — API${RESET}"
echo -e "  cd api && set -a && source ../.env && set +a && ./helpdesk-api"
echo ""
echo -e "  ${CYAN}# Terminal 2 — Frontend${RESET}"
echo -e "  npm run dev"
echo ""
echo -e "  Ou use:  ${BOLD}./setup.sh --start${RESET}  para subir tudo de uma vez."
echo ""

# ─── opcional: subir serviços ────────────────────────────────
if [[ "$START_SERVICES" == true ]]; then
  echo -e "${BOLD}── Iniciando serviços ──────────────────────${RESET}"

  info "Iniciando API em background (log: /tmp/helpdesk-api.log)..."
  cd "$API_DIR"
  set -a; source "$ROOT/.env"; set +a
  nohup ./helpdesk-api > /tmp/helpdesk-api.log 2>&1 &
  API_PID=$!
  sleep 2
  if kill -0 "$API_PID" 2>/dev/null; then
    ok "API rodando (PID $API_PID) → http://localhost:8080"
  else
    fail "API falhou ao iniciar. Verifique /tmp/helpdesk-api.log"
  fi

  info "Iniciando frontend (Vite)..."
  cd "$ROOT"
  npm run dev &
  ok "Frontend iniciando → http://localhost:5173"

  echo ""
  echo -e "  ${YELLOW}Para parar: kill $API_PID && pkill -f 'vite'${RESET}"
fi
