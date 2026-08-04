# Explorar nonRT RIC — Fase 1

Guia prático para as funcionalidades principais do **nonRT RIC O-RAN SC** (PMS, A1 Simulators, Gateway, Control Panel), em paralelo com o lab **FlexRIC + gNB** já validado.

---

## Início rápido

```bash
cd code/oai-cn-gnb-nonrt-nearrt

./scripts/up_nonrt_ric.sh
./scripts/explore_nonrt_ric.sh full
```

| URL | Função |
|-----|--------|
| http://127.0.0.1:8181/ | Control Panel (UI) |
| http://127.0.0.1:8081/status | PMS health (`hunky dory`) |
| http://127.0.0.1:9090/actuator/health | API Gateway |
| http://127.0.0.1:30001/counter/interface | A1 Sim OSC |

---

## Script `explore_nonrt_ric.sh`

| Suite | O que faz |
|-------|-----------|
| `health` | Health checks (padrão) — igual a `test_nonrt_ric.sh` |
| `pms` | Lista RICs, policy types, services e policies via REST |
| `a1sim` | Versão e contadores dos 3 simuladores A1 |
| `policies` | Cria dados de exemplo e verifica no PMS |
| `full` | Todas as suites acima |

```bash
./scripts/explore_nonrt_ric.sh pms
./scripts/explore_nonrt_ric.sh policies
```

---

## 1. Policy Management Service (PMS)

O PMS é o coração do nonRT RIC para **políticas A1**.

```bash
# Status
curl -s http://127.0.0.1:8081/status

# RICs configurados (ric1→OSC, ric2→STD, ric3→STD-v2)
curl -s http://127.0.0.1:8081/a1-policy/v2/rics | jq .

# Policy types conhecidos pelo PMS
curl -s http://127.0.0.1:8081/a1-policy/v2/policy-types | jq .

# Services registados
curl -s http://127.0.0.1:8081/a1-policy/v2/services | jq .
```

Configuração: `config/nonrtric/application_configuration.json` (3 RICs → simuladores A1).

---

## 2. Simuladores A1

Na Fase 1, os simuladores **imitam** um nearRT-RIC para testar o PMS sem ricplt real.

| Simulador | Porta HTTP | Versão A1 |
|-----------|------------|-----------|
| a1-sim-OSC | 30001 | OSC 2.1.0 |
| a1-sim-STD | 30003 | STD 1.1.3 |
| a1-sim-STD-v2 | 30005 | STD 2.0.0 |

```bash
# Versão A1
curl -s http://127.0.0.1:30001/counter/interface

# Número de policy instances
curl -s http://127.0.0.1:30001/counter/num_instances
```

### Criar policy type no simulador

```bash
curl -X PUT "http://127.0.0.1:30001/policytype?id=1" \
  -H "Content-Type: application/json" \
  --data-binary @config/nonrtric/testdata/OSC/policy_type.json
```

Aguarde ~30s para o PMS sincronizar (`policytype_ids` inclui `"1"`).

---

## 3. Ciclo policy completo (PMS → A1 Sim)

```bash
./scripts/test_nonrt_ric.sh --seed
# ou
./scripts/explore_nonrt_ric.sh policies
```

Fluxo:

1. **Policy type** no A1 Sim OSC (`PUT /policytype?id=1`)
2. **Service** no PMS (`PUT /a1-policy/v2/services`)
3. **Policy** no PMS (`PUT /a1-policy/v2/policies`) — PMS encaminha ao nearRT (simulador)

Policy de exemplo: `config/nonrtric/testdata/policy_osc.json`

---

## 4. Control Panel e Gateway

O **Gateway** (`:9090`) faz proxy das APIs A1 para o PMS. O **Control Panel** (`:8181`) é a UI nginx.

```bash
# Via gateway (mesmo path que o PMS)
curl -s http://127.0.0.1:9090/a1-policy/v2/rics | jq .
```

Abra http://127.0.0.1:8181/ após `--seed` para ver policies na UI.

---

## 5. Lab completo (Fase 1 + FlexRIC)

```bash
./scripts/up_e2_lab.sh          # Core + nonRT + FlexRIC + gNB
./scripts/explore_nonrt_ric.sh full
./scripts/explore_e2_sm.sh quick   # E2 nearRT (independente do nonRT)
```

O nonRT RIC **não** comunica com o FlexRIC na Fase 1 — são planos separados.

Para desativar nonRT no lab E2:

```bash
NONRT_RIC=0 ./scripts/up_e2_lab.sh
```

---

## 6. Troubleshooting

| Problema | Solução |
|----------|---------|
| PMS unhealthy | Ver `docs/NONRT_RIC.md` — healthcheck usa bash `/dev/tcp` |
| Policy 404 no PMS | Usar `PUT /a1-policy/v2/policies`, não `/policy-types/.../policies/...` |
| Policy types vazios | Criar no A1 Sim e aguardar sync |
| Porta 8081 ocupada | `NONRT_PMS_HTTP_PORT=18081` em `config/nonrtric/.env` |

```bash
docker compose -f config/nonrtric/docker-compose.yml ps
docker compose -f config/nonrtric/docker-compose.yml logs policy-agent
```

---

## Próximo passo

**Fase 2** — nearRT O-RAN SC (`oran-sc-ric`) + A1 real + gNB E2 porta 36422: [ORAN_RIC_FASE2.md](ORAN_RIC_FASE2.md)
