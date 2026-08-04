#!/bin/sh
set -eu

# Ajuste paths conforme a sua imagem:
# - alguns builds têm "nr-gnb"/"nr-ue"
# - outros têm "gnb"/"ue"
# - outros instalam em /ueransim/bin
#
# Descobrir rápido:
# docker run --rm -it ueransim:latest sh -lc 'ls -R / | grep -iE "nr-gnb|nr-ue|ueransim" | head'

GNB_BIN="${GNB_BIN:-nr-gnb}"
UE_BIN="${UE_BIN:-nr-ue}"

echo "[entrypoint] starting gNB..."
$GNB_BIN -c /etc/ueransim/gnb.yaml &
GNB_PID=$!

sleep 2

echo "[entrypoint] starting UE..."
$UE_BIN -c /etc/ueransim/ue.yaml &
UE_PID=$!

# Mantém o container vivo e propaga sinais
trap "kill $GNB_PID $UE_PID; exit 0" INT TERM
wait $GNB_PID $UE_PID