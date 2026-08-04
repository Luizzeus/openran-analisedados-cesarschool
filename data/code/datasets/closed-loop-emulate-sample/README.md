# Amostra closed-loop (emulate) — opcional / avançado

**Uso:** ilustrar o ciclo KPM → decisão → atuação simulada (`tc`) → efeito → relatório.  
**Não substitui** a amostra UE-TP do projeto; é complemento para quem quiser discutir loop fechado.  
**Origem:** `./scripts/test_closed_loop_lab.sh` (offline, modo `emulate`).  
**Licença / ética:** lab RFSIM; sem dados pessoais; uso acadêmico.

## Conteúdo

| Arquivo | Descrição |
|---------|-----------|
| `kpm.sqlite` / `kpm.jsonl` | Séries usadas no loop |
| `model.json` / `decision.json` / `policy.json` | Treino, decisão e policy candidata |
| `kpm_baseline.log` / `kpm_before.log` / `kpm_after.log` | Janelas textual KPM |
| `effect_report.json` | Deltas before/after (ex.: UEThp, PRB) |
| `actuator_events.jsonl` / `a1_apply.txt` | Auditoria da atuação emulate + dry-run A1 |

## Como regenerar (opcional)

```bash
cd code/oai-cn-gnb-nonrt-nearrt
./scripts/test_closed_loop_lab.sh
# ou live (requer Fase 2):
# ACTUATION_MODE=emulate ./scripts/run_closed_loop_lab.sh --live-fase2
```

Documentação: `code/oai-cn-gnb-nonrt-nearrt/docs/FASE3_CLOSED_LOOP.md`.
