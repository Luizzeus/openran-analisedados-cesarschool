#!/bin/bash
# Script para parar o RAN gNB OAI (gNB + nrUE)
# Uso: ./scripts/down_gnb_oai.sh

set -e

echo "=========================================="
echo "Parando RAN gNB OAI (gNB + nrUE)"
echo "=========================================="
echo ""

# Parar nrUE primeiro
if pgrep -f "nr-uesoftmodem" >/dev/null; then
    echo "Parando nrUE..."
    sudo pkill -f "nr-uesoftmodem" 2>/dev/null || true
    sleep 2
fi

# Parar gNB
if pgrep -f "nr-softmodem" >/dev/null; then
    echo "Parando gNB..."
    sudo pkill -f "nr-softmodem" 2>/dev/null || true
    sleep 2
fi

# Verificar se ainda há processos
if pgrep -f "nr-softmodem|nr-uesoftmodem" >/dev/null; then
    echo "Aviso: Alguns processos ainda podem estar rodando. Use 'pkill -9 -f nr-softmodem' se necessário."
else
    echo "Processos encerrados."
fi

echo ""
echo "=========================================="
echo "gNB OAI parado com sucesso!"
echo "=========================================="
echo ""
echo "💡 Para reiniciar: ./scripts/up_gnb_oai.sh"
echo ""
