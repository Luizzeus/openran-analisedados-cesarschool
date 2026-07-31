# Fase 3 — treinamento de IA e aplicação de policies A1

## Resultado

O projeto passa a ter uma ponte experimental entre telemetria E2/KPM e o
nonRT RIC:

```text
log KPM de baseline -> treino -> model.json
log KPM corrente  -> inferencia -> decision.json -> policy candidata
                                                   |
                                                   +-> dry-run
                                                   +-> PMS / A1 (--commit)
```

O fluxo é um rApp de laboratório. Ele prepara o ciclo de IA/A1 sem afirmar que
a policy já produz uma ação na RAN: para fechar o loop, o Near-RT RIC ainda
precisa ter o `policy type` correspondente e um xApp consumidor que converta a
policy em controle E2.

## Caso de uso local

Para lab virtualizado (OAI+RFSIM), o rApp alinhado ao artigo SUTD é
**UE-TP / load-anomaly** — ver [CASO_USO_LOCAL_VIRTUALIZADO.md](CASO_USO_LOCAL_VIRTUALIZADO.md).
Orquestração com armazenamento:

```bash
./scripts/run_ue_tp_experiment.sh
```

## Componentes

| Artefato | Função |
|----------|--------|
| `config/ai-policy/pipeline.json` | features, limiares e contrato da policy |
| `config/ai-policy/ue_tp_experiment.json` | contrato explícito do caso UE-TP lab |
| `scripts/ai_policy_pipeline.py` | parser KPM, treino, inferência e cliente PMS |
| `scripts/kpm_store.py` | ingestão SQLite + JSONL / export / summary |
| `scripts/run_ai_policy_lab.sh` | execução ponta a ponta (logs → IA → A1) |
| `scripts/run_ue_tp_experiment.sh` | coleta→BD→IA→policy (offline/`--live`) |
| `tests/test_ai_policy_pipeline.py` | testes do parser, inferência e payload |

Não há dependências Python externas. O modelo usa mediana e MAD (median absolute
deviation), uma referência robusta para detectar desvio do baseline. Isso torna
a decisão pequena, reproduzível e auditável; não pretende substituir modelos
supervisionados quando houver dataset rotulado suficiente.

## Dados e features

O parser lê diretamente o formato textual produzido pelo xApp KPM OAI. A
configuração inicial usa:

| Feature | Motivo |
|---------|--------|
| `RRU.PrbTotUl` | detectar saturação de PRBs UL |
| `DRB.RlcSduDelayDl` | detectar degradação de latência |
| `DRB.UEThpUl` | distinguir mudança relevante de carga |

Cada feature recebe um score robusto:

```text
score = abs(valor - mediana_baseline) / max(1.4826 * MAD, mad_floor)
```

Uma amostra é anômala quando ao menos `min_anomalous_features` ultrapassam
`score_threshold`. A janela só decide `apply` quando há maioria de amostras
anômalas, reduzindo reações a um pico isolado.

## Execução rápida

Os defaults usam o baseline e o stress já capturados no repositório:

```bash
./scripts/run_ai_policy_lab.sh
```

O comando:

1. treina e grava `logs/ai_policy_<timestamp>/model.json`;
2. avalia a janela corrente em `decision.json`;
3. mostra a policy candidata, sem enviá-la.

Para usar novas capturas:

```bash
AI_BASELINE_LOG=/dados/kpm_baseline.log \
AI_EVALUATION_LOG=/dados/kpm_atual.log \
./scripts/run_ai_policy_lab.sh
```

Também é possível executar os estágios separadamente:

```bash
python3 scripts/ai_policy_pipeline.py train \
  --input /dados/kpm_baseline.log \
  --config config/ai-policy/pipeline.json \
  --model /tmp/model.json

python3 scripts/ai_policy_pipeline.py evaluate \
  --input /dados/kpm_atual.log \
  --config config/ai-policy/pipeline.json \
  --model /tmp/model.json \
  --output /tmp/decision.json

python3 scripts/ai_policy_pipeline.py apply \
  --decision /tmp/decision.json
```

## Aplicação A1

Antes de aplicar, confirme:

- Fase 2 ativa e PMS respondendo em `http://127.0.0.1:8081/status`;
- `ric-oran` aparece em `/a1-policy/v2/rics`;
- o A1 Mediator anuncia o `policytype_id` configurado;
- `policy_data` satisfaz o JSON Schema desse tipo;
- o `service_id` está cadastrado no PMS;
- existe xApp capaz de consumir esse tipo de policy.

Após revisar `decision.json`, o envio explícito é:

```bash
AI_POLICY_COMMIT=1 ./scripts/run_ai_policy_lab.sh
```

Ou, para um artefato já gerado:

```bash
python3 scripts/ai_policy_pipeline.py apply \
  --decision logs/ai_policy_<timestamp>/decision.json \
  --pms-url http://127.0.0.1:8081/a1-policy/v2 \
  --commit
```

O cliente faz `PUT /a1-policy/v2/policies`. Falhas HTTP ou de conexão terminam
com erro; não existe fallback silencioso. Sem `--commit`, nenhuma chamada de
escrita é realizada.

> O payload inicial segue o policy type 1 usado no simulador da Fase 1. No A1
> real, ele deve ser substituído pelo schema efetivamente publicado pelo xApp
> no A1 Mediator. A presença do endpoint A1, sozinha, não garante efeito na RAN.

## Validação

Testes unitários:

```bash
python3 -m unittest discover -s tests -v
```

Validação integrada e segura:

```bash
AI_RUN_DIR=/tmp/oai-ai-policy-test ./scripts/run_ai_policy_lab.sh
```

Critérios de aceite:

| Etapa | Evidência |
|-------|----------|
| treino | `model.json` contém contagem, medianas e MADs |
| inferência | `decision.json` contém scores, votos e decisão |
| segurança | execução padrão informa `dry-run` |
| A1 | com `--commit`, PMS retorna HTTP 200/201 |
| closed loop | xApp registra recebimento e efeito é medido em KPM posterior |

## Evolução recomendada

1. Exportar KPM estruturado (JSONL/Parquet) com timestamp e identidade de UE.
2. Versionar datasets e registrar métricas de treino/validação.
3. Publicar um policy type próprio para controle de carga no A1 Mediator.
4. Implementar xApp consumidor com limites, TTL e rollback.
5. Comparar KPM antes/depois e só promover modelos que atendam aos guardrails.
6. Adicionar autenticação/TLS antes de sair do host de laboratório.

Policies devem expressar intenção/limites; a ação de baixa latência continua no
xApp via E2. Esse limite preserva a separação nonRT/nearRT da arquitetura O-RAN.
