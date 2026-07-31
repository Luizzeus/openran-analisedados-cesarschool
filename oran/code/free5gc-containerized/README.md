# free5GC + srsRAN — Laboratório 5G SA Containerizado

Laboratório 5G Standalone (SA) com **free5GC** (core) e **srsRAN Project** (RAN) em Docker. O core e a RAN usam **composes separados** e compartilham a rede fixa `free5gc-privnet` (subnet `10.100.200.0/24`).

## Visão geral

```
┌─────────────┐   ZMQ/RU     ┌──────────────────┐    N2/N3     ┌─────────────┐
│   srsUE     │ ◄──────────► │ srsRAN (1 ou 2   │ ◄──────────► │  free5GC    │
│ (opcional)  │              │  containers)     │  NGAP/GTP-U  │  (core)     │
└─────────────┘              └──────────────────┘              └─────────────┘
```

| Pasta | Papel |
|--------|--------|
| **`core/`** | free5GC (AMF, SMF, UPF, NRF, …) — `docker-compose.yaml` só do core |
| **`gNB_traditional/`** | gNB monolítico (`gnb`) — IP **10.100.200.50** |
| **`gNB_disaggregated/`** | Split CU/DU (`srscu` + `srsdu`, F1) — CU **.51**, DU **.52** |
| **`gNB_open/`** | Mesmo split + **Open Fronthaul** (RU emulada, rede `ofhnet`) — mesmos IPs **.51** / **.52** que o desagregado (não usar os dois *stacks* em paralelo) |

## Início rápido

```bash
# 1) Core (cria a rede free5gc-privnet)
cd core
./scripts/validate-ran-stacks.sh  # pré-check dos 3 perfis RAN
./scripts/up.sh
./scripts/add-subscriber.sh    # necessário para UE / sessão PDU

# 2) RAN — escolha UMA stack CU/DU se usar split: gNB_disaggregated OU gNB_open (não ambas).
#    Monolítico gNB_traditional pode coexistir com uma stack CU/DU (gnb_id distinto).
cd ../gNB_traditional && ./scripts/up.sh
# ou: cd ../gNB_disaggregated && ./scripts/up.sh
# ou: cd ../gNB_open && DU_CONFIG=du-ofh-ru-emulator.yml CU_AUTO_START=1 DU_AUTO_START=1 RU_AUTO_START=1 ./scripts/up.sh

# 3) Verificações (sempre a partir de core/)
cd ../core
./scripts/healthcheck.sh
./scripts/validate-n2-ngap.sh
./scripts/test-e2e.sh
```

### Encerrar

```bash
# primeiro a RAN
cd gNB_traditional && ./scripts/down.sh
# ou
cd gNB_disaggregated && ./scripts/down.sh
# ou
cd gNB_open && ./scripts/down.sh

# depois o core
cd ../core
./scripts/down.sh              # preserva volumes Mongo
./scripts/down.sh --volumes    # apaga dados do Mongo
```

## Estrutura

```
free5gc-containerized/
├── README.md
├── core/
│   ├── docker-compose.yaml       # apenas NFs free5GC (+ rede nomeada)
│   ├── Dockerfile.srsRAN         # imagem srsRAN (usada pelas pastas gNB_*)
│   ├── config/ cert/ scripts/ docs/ …
├── gNB_traditional/
│   ├── docker-compose.yaml       # srsran-gnb-tradicional @ 10.100.200.50
│   ├── configs/   logs/
│   └── scripts/
│       ├── up.sh
│       └── down.sh
├── gNB_disaggregated/
│   ├── docker-compose.yaml       # srsran-cu @ .51 + srsran-du @ .52
│   ├── configs/ (cu.yml, du.yml, …)   logs/
│   └── scripts/
│       ├── up.sh
│       └── down.sh
└── gNB_open/
    ├── docker-compose.yaml       # CU + DU + srsran-ru (OFH); rede gnb-open-ofhnet
    ├── configs/   logs/
    └── scripts/
        ├── up.sh
        └── down.sh
```

A detecção de RAN nos scripts de validação em `core/scripts/` usa o helper `scripts/lib/ran-docker.sh` (containers `srsran-cu`, `srsran-gnb-tradicional` ou legado `srsran-gnb`).

## Rede e endereços

| Recurso | IPv4 |
|---------|------|
| Rede Docker | `free5gc-privnet` — 10.100.200.0/24 (`br-free5gc`) |
| AMF (N2) | 10.100.200.16 |
| gNB tradicional | 10.100.200.50 |
| srsCU (RAN aberta) | 10.100.200.51 |
| srsDU | 10.100.200.52 |
| Pool UE (DNN) | 10.60.0.0/16 |
| PLMN | 20893 |

## Notas

- Se já usou uma versão anterior deste lab, a rede Docker passou a chamar-se **`free5gc-privnet`**. Pare stacks antigas e remova redes/containers órfãos se necessário (`docker network ls`, `docker network rm`).
- O arquivo opcional `core/docker-compose-prometheus.yaml` fixa IPs **10.100.200.50** e **.51** — conflitam com **gNB_traditional** (.50) e **CU** do split (.51). Altere os IPs desse compose se precisar de métricas em paralelo com esses labs.

## Requisitos

- Docker e Docker Compose v2  
- IP forwarding (o `core/scripts/up.sh` tenta habilitar)  
- Para UE com ZMQ: srsUE no host — ver `core/docs/CONECTAR_UE.md` (ajuste `gnb-zmq-srsue.yml` em `gNB_traditional/configs/` e troque o arquivo referenciado no `entrypoint.sh` se precisar)

## Laboratórios (aula e relatório)

Roteiros passo a passo, comandos, evidências (prints/logs) e **guia de entrega com rubrica**:

→ **[docs/labs/INDICE.md](docs/labs/INDICE.md)** (roteiros: core, tradicional, desagregado, open/O-RAN)
→ **[docs/labs/00-demo-rapido-3-rans.md](docs/labs/00-demo-rapido-3-rans.md)** (sequência curta para demo dos 3 projetos)

## Documentação (core)

| Documento | Conteúdo |
|-----------|----------|
| [core/docs/SUBSCRIBER_WEBUI_VS_SUBSCRIBERS.md](core/docs/SUBSCRIBER_WEBUI_VS_SUBSCRIBERS.md) | `subscribers` (Mongo) vs lista WebUI (UDR); `add-subscriber.sh` faz ambos |
| [core/docs/CONECTAR_UE.md](core/docs/CONECTAR_UE.md) | srsUE + ZMQ |
| [core/docs/VALIDATION_E2E.md](core/docs/VALIDATION_E2E.md) | N2 / N3 / checklist |
| [core/docs/DOCKER_COMPOSE_EXPLAINED.md](core/docs/DOCKER_COMPOSE_EXPLAINED.md) | Arquitetura Docker (atualize mentalmente: rede agora `free5gc-privnet` nomeada) |

## Referências

- [free5GC](https://free5gc.org/)
- [srsRAN Project](https://github.com/srsran/srsRAN_Project) — CU-DU: `srscu` / `srsdu`
- [srsRAN 4G](https://github.com/srsran/srsRAN_4G) (srsUE)
