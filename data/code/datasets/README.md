# Datasets — Módulo 09

Amostras **versionadas** para a trilha offline do projeto e das aulas práticas. Preferir estes artefatos à regeneração live quando o host não tiver o lab E2.

## Pacotes disponíveis

| Pasta | Uso | Tamanho típico |
|-------|-----|----------------|
| [`kpm-ue-tp-sample/`](kpm-ue-tp-sample/) | **Obrigatório para o projeto** (G1–G7) — KPM SQLite/JSONL + model/decision | ~130 KB |
| [`closed-loop-emulate-sample/`](closed-loop-emulate-sample/) | Opcional — efeito do loop fechado emulate | ~250 KB |

## Regenerar / reempacotar

```bash
# No lab:
cd code/oai-cn-gnb-nonrt-nearrt
./scripts/run_ue_tp_experiment.sh
./scripts/test_closed_loop_lab.sh
