#!/usr/bin/env bash
# Inicia o srsdu sem esperar pelo srsUE. Para ZMQ, prefira ./scripts/start-du-after-ue.sh
# (espera pela porta UL no host — padrão 2003 em gNB_disaggregated; ver configs/ZMQ_PORTS.md).
# Uso: ./scripts/run-du.sh [ficheiro em configs/, padrão: du-zmq-srsue.yml]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
. "${ROOT}/scripts/lib-zmq-du-runtime.sh"
CFG="${1:-du-zmq-srsue.yml}"
YML_IN_CONTAINER="$(prepare_du_yaml_for_container "$ROOT" "$CFG")"
exec docker exec -it srsran-du srsdu -c "${YML_IN_CONTAINER}"
