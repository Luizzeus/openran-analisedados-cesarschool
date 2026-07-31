# Roteiro — Open5GS + srsRAN (RAN real via ZMQ)

**Disciplina:** RAN Intelligent Controller (RIC) · **Aulas 02 e 03**

**Código:** `ric/code/open5gs-container-srsRAN/`

## Objetivos

- Contrastar **UERANSIM** (Aula 01) com **srsRAN Project gNB + srsUE** acoplados por **ZMQ** (amostras IQ em software)
- Aprofundar conceitos de **RAN** (PHY, scheduler, camadas L1/L2) e **abertura de interfaces** (N2/N3 reais; caminho para E2 na pilha OAI — Aulas 04–06)
- Relacionar com **NGO §3** (FlexRIC/OAI) e **Polese** (arquitetura O-RAN) no seminário da Aula 03

## Contexto didático

| Setup | RAN | Rádio | Uso na disciplina |
|-------|-----|-------|-------------------|
| `open5gs-containerized` | UERANSIM | Simulado (sem PHY OAI) | Aula 01 — N1/N2/N3 |
| `open5gs-container-srsRAN` | srsRAN gNB + srsUE | **ZMQ** (IQ entre processos) | Aulas 02–03 — RAN “real” em SW |
| `oai-cn-gnb-e2` | OAI gNB + nrUE | RFSIM ou RF | Aulas 04–06 — E2 + FlexRIC |

O enlace **ZMQ** entre gNB e UE exige **ordem de subida**: o gNB deve transmitir antes do UE; reiniciar só um lado dessincroniza o par.

## Pré-requisitos

- Lab Open5GS da Aula 01 já compreendido
- Docker; imagem srsUE construída localmente (`./scripts/build-srsue.sh`)

## Passos

1. Entrar no diretório:
   ```bash
   cd ric/code/open5gs-container-srsRAN
   ```
2. Subir o core Open5GS:
   ```bash
   ./scripts/up_core.sh
   ```
3. Subir RANs (UERANSIM + srsRAN ZMQ):
   ```bash
   ./scripts/up_ran.sh
   ```
   O script inicia UERANSIM e, se `srsue:latest` existir, o perfil **srsran** (gNB → aguardar → UE).
4. Verificar srsRAN:
   ```bash
   docker compose --profile srsran ps
   docker exec srsran-ue-containerized ip addr show tun_srsue
   ```
5. Comparar com UERANSIM:
   ```bash
   docker compose exec ueransim-ue ip addr show uesimtun0
   ```
6. Logs úteis:
   ```bash
   docker exec srsran-gnb-containerized tail -f /tmp/gnb.log
   docker compose logs -f srsran-ue
   ```

## Aula 02 — foco em sala

- Motivação NGO: validação em **rede 5G real** vs simuladores
- O que muda ao trocar UERANSIM por **srsRAN** (stack L1/L2, ZMQ, tuning de banda/PRB)
- Ponte para **OAI + E2** (NGO Fig. 3 FlexRIC, §5 xApps)

## Aula 03 — foco em sala

- Seminário: correlacionar **abertura de interfaces** (Polese) com os três labs Open5GS
- Bloco docente: retomada A1 + discussão **desagregação** (UERANSIM monólito → gNB∥UE → CU∥DU)
- Próximo passo opcional: `open5gs-container-cudu-srsRAN` (modo `strict-cudu`, F1 entre containers)

## Troubleshooting

| Sintoma | Ação |
|---------|------|
| Imagem `srsue:latest` ausente | `./scripts/build-srsue.sh` |
| UE srsRAN sem attach | Reiniciar **gNB e UE** na ordem do `up_ran.sh` |
| Conflito de PLMN/slice | Conferir `configs/srsRAN/gnb.yaml` e AMF |

## Referências no repositório

- `docs/ESTRUTURA_ARVORE.md`, `docs/PLANO_MIGRACAO.md`
- Próximo lab: [02-oai-cn-gnb-flexric-e2.md](02-oai-cn-gnb-flexric-e2.md)
