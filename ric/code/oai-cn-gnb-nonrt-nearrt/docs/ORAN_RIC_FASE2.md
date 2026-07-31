# nearRT O-RAN SC + A1 — Fase 2

Stack **nearRT O-RAN SC** (`oran-sc-ric`) com gNB OAI em E2 porta **36422**, opcionalmente ligado ao **nonRT RIC** via **A1 Mediator** (`ric-plt-a1`).

> A **Fase 1** permanece inalterada (`up_nonrt_ric.sh`, simuladores A1, FlexRIC :36421).

---

## Perfis RIC

| Perfil | Comando | nearRT | E2 porta | nonRT |
|--------|---------|--------|----------|-------|
| **Fase 1** | `up_e2_lab.sh` | FlexRIC | 36421 | PMS + A1 Sim |
| **Fase 2** | `up_oai_oran_lab.sh` | oran-sc-ric | **36422** | PMS → A1 Mediator |

**Não executar FlexRIC e oran-sc-ric em simultâneo** (conflito de recursos E2).

---

## Início rápido

```bash
cd code/oai-cn-gnb-nonrt-nearrt

# 1. Compilar gNB com E2 :36422 (binário separado)
./scripts/build_e2_oran_sc.sh

# 2. Lab completo Fase 2
./scripts/up_oai_oran_lab.sh

# 3. Testar e explorar
./scripts/test_oran_ric.sh
./scripts/explore_oran_ric.sh full
```

Sem nonRT na Fase 2:

```bash
NONRT_RIC=0 ./scripts/up_oai_oran_lab.sh
```

Parar:

```bash
./scripts/down_oai_oran_lab.sh
```

---

## Componentes

### nearRT (`vendor/oran-sc-ric` + `config/oran-ric/`)

| Container | Função |
|-----------|--------|
| `ric_e2term` | E2 Termination — SCTP **36422** (host) |
| `ric_e2mgr` | E2 Manager |
| `ric_submgr` | Subscription Manager |
| `ric_appmgr` | xApp Manager |
| `ric_dbaas` | Redis SDL |
| `ric_rtmgr_sim` | Routing Manager Simulator |
| `python_xapp_runner` | xApps Python |
| `ric_a1mediator` | A1 Mediator (nonRT ↔ xApps) |

### nonRT perfil oran (`docker-compose.oran.yml`)

PMS + Gateway + Control Panel **sem** simuladores A1. `ric-oran` aponta para `http://a1mediator:10000/a1-p/`.

---

## Scripts

| Script | Função |
|--------|--------|
| `up_oran_ric.sh` / `down_oran_ric.sh` | nearRT O-RAN SC |
| `up_nonrt_ric_oran.sh` | nonRT perfil A1 real |
| `build_e2_oran_sc.sh` | gNB `nr-softmodem-oran-sc` (:36422) |
| `up_gnb_oai_oran.sh` | gNB + UE → oran-sc-ric |
| `up_oai_oran_lab.sh` | Lab completo Fase 2 |
| `test_oran_ric.sh` | Validação (`--run-xapp` para smoke test KPM) |
| `run_xapp_oai_kpm.sh` | xApp KPM OAI (Style 4, recomendado) |
| `stop_xapp_oai_kpm.sh` | Parar xApps órfãos no container |
| `get_oran_e2_node_id.sh` | E2 Node ID no RNIB |
| `explore_oran_ric.sh` | Exploração (health, E2, A1, xApp) |

---

## xApp KPM (gNB OAI)

**Guia completo:** [XAPP_KPM_OAI_ORAN.md](XAPP_KPM_OAI_ORAN.md) — arranque, verificação de INDICATIONs, tráfego UE, troubleshooting.

Resumo:

```bash
./scripts/test_oran_ric.sh
KPM_TRAFFIC=1 ./scripts/run_xapp_oai_kpm.sh
```

> Use `simple_xapp_oai.py`, **não** `simple_mon_xapp.py` (Style 1 incompatível com o agente E2 OAI).

---

## RNIB Redis (correção)

O `ric-plt-dbaas:0.6.4` usa Redis 6.2, incompatível com o cliente go-redis do e2mgr/submgr (`got 7 elements in COMMAND reply, wanted 6`).

**Solução aplicada:** `DBAAS_VER=0.5.0` (Redis 5.0.9) em `config/oran-ric/.env`.

```bash
./scripts/fix_oran_ric_rnib.sh    # recria dbaas + reinicia e2mgr/submgr
./scripts/up_gnb_oai_oran.sh      # E2 via 10.0.2.10 (rede Docker, não localhost)
./scripts/get_oran_e2_node_id.sh  # ex: gnb_208_095_00000e00
./scripts/test_oran_ric.sh        # termina em segundos (xApp omitido)
./scripts/test_oran_ric.sh --run-xapp   # xApp KPM opcional (~12s)
```

## Verificação E2

```bash
grep -iE 'E2|RIC|setup' logs/gnb_oai_oran.log | tail -20
docker logs ric_e2term 2>&1 | tail -30
docker exec ric_dbaas redis-cli KEYS '{e2Manager},RAN:gnb_*'
```

**Nota:** O-RAN SC usa timeout de 60s após desconexão E2 antes de aceitar novo SETUP.

---

## A1 (nonRT ↔ nearRT)

```bash
curl -s http://127.0.0.1:10000/a1-p/healthcheck
curl -s http://127.0.0.1:10000/a1-p/policytypes/
curl -s http://127.0.0.1:8081/a1-policy/v2/rics | jq .
```

A integração A1 completa (policy end-to-end PMS → xApp) depende de xApps que consumam políticas via RMR — em evolução.

---

## Voltar à Fase 1

```bash
./scripts/down_oai_oran_lab.sh
./scripts/up_e2_lab.sh    # FlexRIC + simuladores A1
```

---

## Referências

- [srsran/oran-sc-ric](https://github.com/srsran/oran-sc-ric)
- [OAI E2AP §5 O-RAN SC](openairinterface5g/openair2/E2AP/README.md)
- [ric-plt-a1](https://docs.o-ran-sc.org/projects/o-ran-sc-ric-plt-a1/en/stable/)
- [EXPLORAR_NONRT_RIC.md](EXPLORAR_NONRT_RIC.md) — Fase 1
