# nonRT RIC O-RAN SC — Fase 1

Deploy do **non-RT RIC** da O-RAN Software Community em Docker, em paralelo com o lab **nearRT FlexRIC** + **gNB OAI** já validado.

> **Fase 1:** PMS + simuladores A1 + Control Panel. **Sem** ligação A1 real ao FlexRIC (isso é Fase 2 com `oran-sc-ric`).

---

## Componentes

| Container | Função | Porta host |
|-----------|--------|------------|
| `nonrt-policy-agent` | A1 Policy Management Service (PMS) | 8081 (HTTP), 8433 (HTTPS) |
| `a1-sim-OSC` | Simulador nearRT — A1 OSC 2.1.0 | 30001 |
| `a1-sim-STD` | Simulador nearRT — A1 STD 1.1.3 | 30003 |
| `a1-sim-STD-v2` | Simulador nearRT — A1 STD 2.0.0 | 30005 |
| `nonrtric-gateway` | API Gateway (Control Panel → PMS) | 9090 |
| `nonrt-control-panel` | UI web | **8181** |

Rede Docker: `oran-nonrt-net`

Configuração: `config/nonrtric/`

---

## Explorar funcionalidades

Guia detalhado e script interativo:

```bash
./scripts/explore_nonrt_ric.sh full   # health + PMS + A1 sim + policies
```

Ver [EXPLORAR_NONRT_RIC.md](EXPLORAR_NONRT_RIC.md).

## Início rápido

```bash
cd code/oai-cn-gnb-nonrt-nearrt

# Só nonRT RIC
./scripts/up_nonrt_ric.sh
./scripts/test_nonrt_ric.sh --seed

# Lab completo (Core + nonRT + FlexRIC nearRT + gNB)
./scripts/up_e2_lab.sh

# Parar
./scripts/down_nonrt_ric.sh
# ou
./scripts/down_e2_lab.sh
```

**Control Panel:** http://127.0.0.1:8181/

Com `--seed`, o teste cria policy type, service e policy de exemplo visíveis na UI.

---

## Verificação manual

```bash
# PMS
curl -s http://127.0.0.1:8081/status

# A1 simulators
curl -s http://127.0.0.1:30001/counter/interface
curl -s http://127.0.0.1:30005/counter/interface

# RICs no PMS
curl -s http://127.0.0.1:8081/a1-policy/v2/rics | jq .

# Logs
docker compose -f config/nonrtric/docker-compose.yml logs -f policy-agent
```

---

## Arquitetura Fase 1

```
┌─────────────────────────────────────────────────────────┐
│  nonRT RIC (Docker — oran-nonrt-net)                    │
│  Control Panel :8181 → Gateway :9090 → PMS :8081        │
│                              │                          │
│                    A1 (HTTP) ▼                          │
│         a1-sim-OSC / a1-sim-STD / a1-sim-STD-v2         │
│         (simulam nearRT — não é o FlexRIC real)         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  nearRT FlexRIC (host) :36421  ←E2→  gNB OAI            │
│  (inalterado na Fase 1)                                 │
└─────────────────────────────────────────────────────────┘
```

---

## Variáveis de ambiente

| Variável | Default | Descrição |
|----------|---------|-----------|
| `NONRT_COMPOSE_DIR` | `config/nonrtric` | Path do compose |
| `NONRT_PMS_HTTP_PORT` | `8081` | PMS HTTP |
| `NONRT_CONTROL_PANEL_PORT` | `8181` | UI |
| `NONRT_GATEWAY_PORT` | `9090` | Gateway |
| `NONRT_RIC` | `1` | Em `up_e2_lab.sh`, `0` desativa nonRT |

Imagens em `config/nonrtric/.env` (registry `nexus3.o-ran-sc.org`).

---

## Troubleshooting

### Imagens não descarregam

Requer acesso à internet e ao registry O-RAN SC:

```bash
docker pull nexus3.o-ran-sc.org:10002/o-ran-sc/nonrtric-a1-policy-management-service:2.3.1
```

### PMS não fica healthy

```bash
docker compose -f config/nonrtric/docker-compose.yml logs policy-agent
```

Aguardar até 90s no primeiro arranque (JVM).

### Porta 8081 em uso

Alterar em `config/nonrtric/.env`: `NONRT_PMS_HTTP_PORT=18081`

### Control Panel vazio

Executar `./scripts/test_nonrt_ric.sh --seed` para criar dados de exemplo.

---

## Próximo passo (Fase 2)

Substituir simuladores A1 por **nearRT O-RAN SC** (`oran-sc-ric`) e ligar PMS → ricplt via A1 real, com gNB E2 na porta **36422**.

Ver [PLANO_INTEGRACAO_NONRT_RIC_SMO.md](PLANO_INTEGRACAO_NONRT_RIC_SMO.md).

---

## Referências

- [O-RAN SC nonrtric docker-compose](https://github.com/o-ran-sc/nonrtric/tree/master/docker-compose)
- [Release L - Run in Docker (RICNR)](https://lf-o-ran-sc.atlassian.net/wiki/spaces/RICNR/pages/446759174)
