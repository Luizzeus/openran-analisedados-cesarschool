#!/bin/bash
#
# Corrige terminações de linha em todos os scripts .sh
# Remove CRLF (Windows) e converte para LF (Unix)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=========================================="
echo "🔧 Corrigindo Terminações de Linha"
echo "=========================================="
echo ""

# Encontrar e corrigir todos os scripts .sh
FIXED=0
for script in $(find . -name "*.sh" -type f); do
    # Verificar se tem CRLF
    if file "$script" | grep -q "CRLF"; then
        echo "📝 Corrigindo: $script"
        sed -i 's/\r$//' "$script"
        chmod +x "$script" 2>/dev/null || true
        ((FIXED++))
    fi
done

if [ $FIXED -eq 0 ]; then
    echo "✅ Nenhum arquivo precisa ser corrigido"
else
    echo ""
    echo "✅ $FIXED arquivo(s) corrigido(s)"
fi

echo ""
echo "=========================================="
echo "✅ Concluído!"
echo "=========================================="
echo ""
