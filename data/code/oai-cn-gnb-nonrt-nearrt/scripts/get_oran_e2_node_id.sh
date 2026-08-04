#!/bin/bash
# Obtém o E2 Node ID registado no RNIB (Redis) para xApps O-RAN SC.
# Uso: ./scripts/get_oran_e2_node_id.sh

set -euo pipefail

if ! docker inspect ric_dbaas >/dev/null 2>&1; then
    echo "ERRO: ric_dbaas não está em execução." >&2
    exit 1
fi

# Chaves RNIB: {e2Manager},RAN:gnb_MCC_MNC_NBID
mapfile -t keys < <(docker exec ric_dbaas redis-cli KEYS '{e2Manager},RAN:gnb_*' 2>/dev/null | grep -v '^$' || true)

if [ "${#keys[@]}" -eq 0 ]; then
    echo "ERRO: Nenhum RAN no RNIB. Verifique E2 SETUP no gNB." >&2
    exit 1
fi

# Preferir entrada com PLMN OAI (208/95) se existir
for k in "${keys[@]}"; do
    id="${k##*:}"
    if [[ "$id" == gnb_208_095_* ]]; then
        echo "$id"
        exit 0
    fi
done

echo "${keys[0]##*:}"
