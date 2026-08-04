# Projeto prático — alinhamento ao plano de ensino (Módulo 09)

**Caminho:** `code/oai-cn-gnb-nonrt-nearrt`  
**Índice operacional:** [`../code/oai-cn-gnb-nonrt-nearrt/docs/FASES_ORAN_LAB.md`](../code/oai-cn-gnb-nonrt-nearrt/docs/FASES_ORAN_LAB.md)  
**Caso de uso (rApp UE-TP):** [`../code/oai-cn-gnb-nonrt-nearrt/docs/CASO_USO_LOCAL_VIRTUALIZADO.md`](../code/oai-cn-gnb-nonrt-nearrt/docs/CASO_USO_LOCAL_VIRTUALIZADO.md)  
**Briefing avaliativo:** [`briefing-projeto.md`](briefing-projeto.md)  
**Temas dos 7 grupos:** [`temas-grupos.md`](temas-grupos.md) · docente: [`temas-grupos-docente.md`](temas-grupos-docente.md)

## Veredito de alinhamento

O laboratório fecha o ciclo da ementa — **fontes → armazenamento → EDA/ETL → KPIs → recomendação/política A1 simulada** — de forma executável. É o laboratório da prática integradora (RAN/E2/KPM). Core, transporte e terminais entram por exemplos e estudos de caso.

| Objetivo específico (plano) | Evidência no laboratório / disciplina |
|-----------------------------|----------------------------------------|
| Mapear fontes RAN/core/transporte/terminais | E2 KPM + exemplos conceituais de CDRs, latência/perda e QoE |
| Comparar *data lake* / *data warehouse* | JSONL + SQLite (`kpm_store.py`) como bronze/curado |
| Aplicar EDA/ETL (Python) | Parser KPM, atributos, análise proporcional |
| Interpretar KPI/KQI/QoS/QoE | Ex.: `RRU.PrbTotUl`, `DRB.RlcSduDelayDl`, `DRB.UEThpUl` |
| Capacidade / otimização → A1 simulada | Anomalia de carga → política A1 candidata (execução simulada) |
| Pipeline reprodutível documentado | README + artefatos + apresentação/defesa |
| Governança e limites | Execução simulada padrão; limites RFSIM |

## Progressão do projeto (checkpoints)

| Aula | Data | Marco |
|------|------|--------|
| **01** | 04/08/2026 | Apresentação do problema integrador e briefing |
| **02** | 06/08/2026 | Caso/tema do grupo (card G1–G7), fonte e arquitetura preliminares |
| **03** | 08/08/2026 | Checkpoint 1 — ingestão, qualidade, KPIs preliminares (trilha offline) |
| **04** | 25/08/2026 | Checkpoint 2 — validação de KPIs/KQIs e visualizações |
| **05** | 27/08/2026 | Checkpoint técnico final — análise, limitações, recomendação/A1 |
| **06** | 29/08/2026 | Integração, apresentação e defesa individual |

## Trilhas

- **Trilha offline (obrigatória para avaliação):** artefatos KPM disponibilizados pelo docente; regeneráveis com `./scripts/run_ue_tp_experiment.sh` quando houver ambiente.
- **Trilha ao vivo (opcional/avançada):** laboratório E2 no ar + `--live`; commit A1 somente com `AI_POLICY_COMMIT=1`.

Dificuldades de infraestrutura não determinam a nota quando a trilha offline for seguida.

## O que não substitui

- Exercícios individuais `#data/*` (**30%**).
- Engajamento técnico e checkpoints (**20%**).
- Briefing formal do projeto (**50%**).
