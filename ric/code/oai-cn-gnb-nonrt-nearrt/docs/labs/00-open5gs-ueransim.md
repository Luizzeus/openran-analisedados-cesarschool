# Roteiro — Lab Open5GS + UERANSIM

**Disciplina:** RAN Intelligent Controller (RIC) · **Aula 01**

**Código:** `ric/code/open5gs-containerized/`

## Objetivos

- Subir o core 5G SA containerizado (Open5GS) e o RAN simulado (UERANSIM gNB + UE)
- Mapear interfaces **N1** (NAS), **N2** (NGAP/SCTP) e **N3** (GTP-U) no setup
- Identificar o que o lab **não** cobre ainda (E2, Near-RT RIC, splits O-RAN) — encaminhamento para Aulas 02–03

## Pré-requisitos

- Docker 20.10+ e Docker Compose 2.0+
- Ubuntu 22.04+ (recomendado), ~4 GB RAM livres

## Passos

1. Entrar no diretório do lab:
   ```bash
   cd ric/code/open5gs-containerized
   ```
2. Subir o **core** (SBI) primeiro:
   ```bash
   ./scripts/up_core.sh
   ```
3. Subir o **RAN** (gNB + UE UERANSIM):
   ```bash
   ./scripts/up_ran.sh
   ```
4. Verificar saúde e conectividade:
   ```bash
   ./scripts/healthcheck.sh
   ./scripts/test_ue_connection.sh
   ```
5. Inspecionar configurações didáticas:
   - `ueransim/configs/gnb.yaml` — PLMN, TAC, slice, N2/N3
   - `ueransim/configs/ue.yaml` — USIM, DNN, ciphering
6. Encerrar (RAN antes do core):
   ```bash
   ./scripts/down_ran.sh
   ./scripts/down_core.sh
   ```

## O que observar em sala

| Interface | Protocolo | Onde ver |
|-----------|-----------|----------|
| N2 | NGAP/SCTP | Logs gNB UERANSIM, AMF Open5GS |
| N3 | GTP-U | SMF/UPF, interface `uesimtun0` no UE |
| SBI | HTTP/2 | NRF, AMF, SMF entre si |

## Troubleshooting rápido

| Sintoma | Ação |
|---------|------|
| `slice-not-supported` no NG Setup | Alinhar TAC/PLMN/slice em `gnb.yaml` e `amf.yaml` |
| `network core_net-n2 not found` | Subir o core antes do UERANSIM |
| UE sem IP | Verificar PDU session, DNN `internet`, UPF healthy |

## Próximo passo (Aula 02)

Introdução à **RAN real** com **srsRAN + ZMQ** (`code/open5gs-container-srsRAN/`) para aprofundar PHY/MAC e abertura de interfaces em relação ao UERANSIM.
