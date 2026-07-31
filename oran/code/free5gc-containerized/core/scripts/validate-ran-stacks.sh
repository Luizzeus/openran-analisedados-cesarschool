#!/usr/bin/env bash
# Validate the three RAN stacks used by this lab without starting containers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd "${CORE_DIR}/.." && pwd)"

ERRORS=0
WARNINGS=0

ok() {
  printf '[OK] %s\n' "$*"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf '[WARN] %s\n' "$*"
}

fail() {
  ERRORS=$((ERRORS + 1))
  printf '[FAIL] %s\n' "$*"
}

require_dir() {
  local path="$1"
  [ -d "$path" ] && ok "Directory exists: ${path#$ROOT_DIR/}" || fail "Missing directory: ${path#$ROOT_DIR/}"
}

require_file() {
  local path="$1"
  [ -f "$path" ] && ok "File exists: ${path#$ROOT_DIR/}" || fail "Missing file: ${path#$ROOT_DIR/}"
}

require_exec() {
  local path="$1"
  [ -x "$path" ] && ok "Executable: ${path#$ROOT_DIR/}" || fail "Not executable: ${path#$ROOT_DIR/}"
}

require_grep() {
  local pattern="$1"
  local path="$2"
  local message="$3"
  grep -Eq "$pattern" "$path" && ok "$message" || fail "$message"
}

compose_config() {
  local dir="$1"
  local name="$2"
  if (cd "$dir" && docker compose config --quiet >/dev/null); then
    ok "Compose config valid: ${name}"
  else
    fail "Compose config invalid: ${name}"
  fi
}

echo "== Static structure =="
require_dir "$CORE_DIR"
require_dir "$ROOT_DIR/gNB_traditional"
require_dir "$ROOT_DIR/gNB_disaggregated"
require_dir "$ROOT_DIR/gNB_open"

require_file "$CORE_DIR/docker-compose.yaml"
require_file "$ROOT_DIR/gNB_traditional/docker-compose.yaml"
require_file "$ROOT_DIR/gNB_disaggregated/docker-compose.yaml"
require_file "$ROOT_DIR/gNB_open/docker-compose.yaml"

echo ""
echo "== Compose files =="
compose_config "$CORE_DIR" "core"
compose_config "$ROOT_DIR/gNB_traditional" "gNB_traditional"
compose_config "$ROOT_DIR/gNB_disaggregated" "gNB_disaggregated"
compose_config "$ROOT_DIR/gNB_open" "gNB_open"

echo ""
echo "== Expected RAN addressing =="
require_grep 'ipv4_address:[[:space:]]*10\.100\.200\.50' "$ROOT_DIR/gNB_traditional/docker-compose.yaml" "traditional gNB uses 10.100.200.50"
require_grep 'name:[[:space:]]*free5gc-privnet' "$ROOT_DIR/gNB_traditional/docker-compose.yaml" "traditional gNB uses free5gc-privnet"
require_grep 'GNB_AUTO_START:.*:-1' "$ROOT_DIR/gNB_traditional/docker-compose.yaml" "traditional gNB auto-start default is enabled"

require_grep 'ipv4_address:[[:space:]]*10\.100\.200\.51' "$ROOT_DIR/gNB_disaggregated/docker-compose.yaml" "disaggregated CU uses 10.100.200.51"
require_grep 'ipv4_address:[[:space:]]*10\.100\.200\.52' "$ROOT_DIR/gNB_disaggregated/docker-compose.yaml" "disaggregated DU uses 10.100.200.52"
require_grep 'name:[[:space:]]*free5gc-privnet' "$ROOT_DIR/gNB_disaggregated/docker-compose.yaml" "disaggregated stack uses free5gc-privnet"

require_grep 'ipv4_address:[[:space:]]*10\.100\.200\.51' "$ROOT_DIR/gNB_open/docker-compose.yaml" "open CU uses 10.100.200.51"
require_grep 'ipv4_address:[[:space:]]*10\.100\.200\.52' "$ROOT_DIR/gNB_open/docker-compose.yaml" "open DU uses 10.100.200.52"
require_grep 'name:[[:space:]]*free5gc-privnet' "$ROOT_DIR/gNB_open/docker-compose.yaml" "open stack uses free5gc-privnet"
require_grep 'name:[[:space:]]*gnb-open-ofhnet' "$ROOT_DIR/gNB_open/docker-compose.yaml" "open stack defines OFH network"
require_grep 'container_name:[[:space:]]*srsran-ru' "$ROOT_DIR/gNB_open/docker-compose.yaml" "open stack defines RU emulator container"

echo ""
echo "== Helper scripts =="
require_exec "$ROOT_DIR/gNB_traditional/scripts/up.sh"
require_exec "$ROOT_DIR/gNB_traditional/scripts/down.sh"
require_exec "$ROOT_DIR/gNB_disaggregated/scripts/up.sh"
require_exec "$ROOT_DIR/gNB_disaggregated/scripts/down.sh"
require_exec "$ROOT_DIR/gNB_disaggregated/scripts/start-cu.sh"
require_exec "$ROOT_DIR/gNB_disaggregated/scripts/start-du-after-ue.sh"
require_exec "$ROOT_DIR/gNB_open/scripts/up.sh"
require_exec "$ROOT_DIR/gNB_open/scripts/down.sh"
require_exec "$ROOT_DIR/gNB_open/scripts/start-cu.sh"
require_exec "$ROOT_DIR/gNB_open/scripts/start-du-after-ue.sh"
require_exec "$ROOT_DIR/gNB_open/scripts/start-ru-emulator.sh"
require_exec "$ROOT_DIR/gNB_open/scripts/start-du-ofh.sh"

echo ""
echo "== Path consistency =="
OLD_PATH_PATTERN="$(printf 'gNB_%s\\|gNB_%s' 'desagregated' 'tradicional')"
if grep -RIl --exclude='validate-ran-stacks.sh' "$OLD_PATH_PATTERN" "$ROOT_DIR" >/dev/null 2>&1; then
  fail "Old directory names remain in repository text"
  grep -RIn --exclude='validate-ran-stacks.sh' "$OLD_PATH_PATTERN" "$ROOT_DIR" || true
else
  ok "No old gNB directory names found"
fi

echo ""
echo "== Docker daemon preflight =="
if docker info >/dev/null 2>&1; then
  ok "Docker daemon is reachable"
  if docker network inspect free5gc-privnet >/dev/null 2>&1; then
    subnet="$(docker network inspect free5gc-privnet -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || true)"
    [ "$subnet" = "10.100.200.0/24" ] && ok "free5gc-privnet subnet is 10.100.200.0/24" || warn "free5gc-privnet subnet is '${subnet:-unknown}', expected 10.100.200.0/24"
  else
    warn "free5gc-privnet does not exist yet; run core/scripts/up.sh before any gNB stack"
  fi

  if docker image inspect srsran-gnb:local >/dev/null 2>&1; then
    ok "srsran-gnb:local image is present"
  else
    warn "srsran-gnb:local image is not present yet; first RAN up will build it from core/Dockerfile.srsRAN"
  fi
else
  warn "Docker daemon is not reachable; skipped runtime preflight"
fi

echo ""
echo "== Summary =="
printf 'Errors: %s\n' "$ERRORS"
printf 'Warnings: %s\n' "$WARNINGS"

[ "$ERRORS" -eq 0 ]
