# Roteiro 00 — Demo rápida (core + 3 RANs)

Guia curto para demonstração em sala, validando em sequência:

1. `core` (free5GC)
2. `gNB_traditional` (monolítico)
3. `gNB_disaggregated` (CU/DU split)
4. `gNB_open` (CU/DU + Open Fronthaul com RU emulada)

## 0) Pré-checks

Na raiz `free5gc-containerized/`:

```bash
docker ps
```

Se houver stacks antigas ativas, pare antes de iniciar a demo.

## 1) Subir o core

```bash
cd core
./scripts/up.sh
./scripts/healthcheck.sh
```

Critério de sucesso:

- `db`, `nrf`, `amf`, `smf`, `upf` em `Up`.
- Sem erro de rede `free5gc-privnet`.

## 2) Demo 1: RAN tradicional

```bash
cd ../gNB_traditional
GNB_AUTO_START=1 ./scripts/up.sh

cd ../core
./scripts/validate-n2-ngap.sh
```

Critério de sucesso:

- `validate-n2-ngap.sh` termina com `N2/NGAP validado com sucesso`.
- Container `srsran-gnb-tradicional` com `RestartCount = 0`.

Encerrar antes do próximo cenário:

```bash
cd ../gNB_traditional
./scripts/down.sh
```

## 3) Demo 2: RAN desagregada (CU/DU)

Sem UE (fluxo estável para demo de interfaces):

```bash
cd ../gNB_disaggregated
DU_CONFIG=du.yml CU_AUTO_START=1 DU_AUTO_START=1 ./scripts/up.sh

cd ../core
./scripts/validate-n2-ngap.sh
```

Critério de sucesso:

- `srsran-cu` e `srsran-du` em `Up`.
- `validate-n2-ngap.sh` em sucesso.
- DU com F1-C conectado ao CU (em `gNB_disaggregated/logs/du.log`).

Encerrar antes do próximo cenário:

```bash
cd ../gNB_disaggregated
./scripts/down.sh
```

## 4) Demo 3: RAN aberta (Open Fronthaul)

```bash
cd ../gNB_open
DU_CONFIG=du-ofh-ru-emulator.yml CU_AUTO_START=1 DU_AUTO_START=1 RU_AUTO_START=1 ./scripts/up.sh
./scripts/verify-ofh.sh

cd ../core
./scripts/validate-n2-ngap.sh
```

Critério de sucesso:

- `srsran-cu`, `srsran-du`, `srsran-ru` em `Up`.
- `verify-ofh.sh` mostra `eth1` no DU e `eth0` no RU na rede OFH.
- `validate-n2-ngap.sh` em sucesso.

## 5) Encerramento final

```bash
cd ../gNB_open
./scripts/down.sh

cd ../core
./scripts/down.sh
```

## Notas de operação para evitar falhas em demo

- `gNB_disaggregated` e `gNB_open` nao podem subir juntos (mesmos nomes/IPs de CU/DU).
- `gNB_open/scripts/*.sh` deve estar executável. Se necessário:
  `chmod +x gNB_open/scripts/*.sh`
- Para demo com UE (ZMQ), use ordem: `CU -> srsUE -> DU`.
