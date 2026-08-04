#!/bin/bash
# Adiciona usuários 31 e 32 ao AccessAndMobilitySubscriptionData
# Necessário apenas quando o banco foi criado ANTES da correção no oai_db2.sql
# Para novos deploys, os usuários já estão em oai_db2.sql — não é necessário rodar.
# Uso: ./scripts/fix-ue-subscriber.sh

set -e

echo "Adicionando usuários 31 e 32 ao AccessAndMobilitySubscriptionData..."
docker exec mysql mysql -u test -ptest oai_db -e "
INSERT IGNORE INTO AccessAndMobilitySubscriptionData (ueid, servingPlmnid, nssai) 
VALUES 
  ('208950000000031', '20895', '{\"defaultSingleNssais\": [{\"sst\": 222, \"sd\": \"123\"}]}'),
  ('208950000000032', '20895', '{\"defaultSingleNssais\": [{\"sst\": 222, \"sd\": \"123\"}]}');
" 2>/dev/null && echo "✓ Usuários adicionados." || echo "Erro ou usuários já existem."
echo ""
echo "Reinicie RAN: ./scripts/down_all.sh && ./scripts/up_all.sh"
