# Amostra KPM — UE-TP / load-anomaly (trilha offline)

**Uso:** fonte preferencial do projeto integrador (Aulas 03–06) e EDA da Aula 03.  
**Origem:** lab `oai-cn-gnb-nonrt-nearrt`, experimento offline regenerado em 2026-08-04 (`ue-tp-20260804-174422`).  
**Licença / ética:** telemetria sintética de laboratório RFSIM (OAI); sem dados pessoais; uso apenas acadêmico neste módulo.

## Conteúdo

| Arquivo | Descrição |
|---------|-----------|
| `kpm.sqlite` | Base curada (fases `baseline` / `stress` / `recovery`) |
| `kpm.jsonl` | Mesmos pontos em JSONL (bronze/análise ad hoc) |
| `db_summary.json` | Contagem por fase |
| `model.json` | Modelo MAD treinado no baseline |
| `decision.json` | Decisão `apply` + contexto (dry-run A1) |
| `baseline_from_db.log` / `stress_from_db.log` | Extratos textuais auxiliares |

## Métricas presentes (exemplos)

`DRB.UEThpDl`, `DRB.UEThpUl`, `DRB.RlcSduDelayDl`, `RRU.PrbTotUl`, volumes PDCP, etc.

## Como regenerar (opcional)

```bash
cd code/oai-cn-gnb-nonrt-nearrt
./scripts/run_ue_tp_experiment.sh
# artefatos em logs/experiments/ue-tp-<timestamp>/
```

## Leitura rápida (Python)

```python
import sqlite3, pandas as pd
from pathlib import Path
db = Path("code/datasets/kpm-ue-tp-sample/kpm.sqlite")
con = sqlite3.connect(db)
print(pd.read_sql("SELECT name FROM sqlite_master WHERE type='table'", con))
# Ajuste o nome da tabela após inspecionar o schema
```

Ver também: `docs/briefing-projeto.md`, `docs/temas-grupos.md`, lab `docs/CASO_USO_LOCAL_VIRTUALIZADO.md`.
