# Briefing — Projeto integrador em grupo (50%)

## Objetivo

Principal trabalho avaliativo da disciplina: entregar um **pipeline analítico reproduzível** sobre telemetria RAN (laboratório local), com definição explícita de KPIs/KQIs, visualizações, recomendação operacional ou política A1 em execução simulada, discussão de limitações e **apresentação com defesa individual na Aula 06 (29/08/2026)**.

Este briefing está disponível desde o início do módulo. O projeto avança por checkpoints (Aulas 02–05); a Aula 06 concentra integração, apresentação e defesa.

## Fonte de dados (trilha offline obrigatória)

Laboratório `code/oai-cn-gnb-nonrt-nearrt` — caso **UE-TP / load-anomaly**.

Referência obrigatória para avaliação: **artefatos KPM disponibilizados pelo docente** (trilha offline/reproduzível):

```text
code/datasets/kpm-ue-tp-sample/   # pacote padrão (ZIP / repositório)
```

Quando houver ambiente disponível, o estudante pode regenerar artefatos com:

```bash
cd code/oai-cn-gnb-nonrt-nearrt
./scripts/run_ue_tp_experiment.sh          # offline (padrão)
./scripts/run_ue_tp_experiment.sh --live   # se o laboratório E2 estiver no ar
```

Artefatos típicos: SQLite/JSONL, `model.json`, `decision.json`, política A1 candidata em execução simulada (*dry-run*). Ver [`PACOTE_ALUNO.md`](PACOTE_ALUNO.md).

Outras fontes somente com autorização do docente (ex.: subset SUTD licenciado).

**Dificuldades de infraestrutura não determinam a nota** quando a trilha offline for utilizada corretamente.

## Escopo da análise (proporcional à carga horária)

Admitem-se: regras por limiares, agregações estatísticas, regressão simples, detecção básica de anomalias ou classificação simples quando justificável. Não se exige aprendizado de máquina sofisticado.

## Entregáveis

1. Repositório ou pasta versionada com README (origem dos dados, como reproduzir, ética/licença).
2. Scripts/notebooks de ETL e análise.
3. Definição formal de **pelo menos 2 KPIs/KQIs** (fórmula, granularidade, fonte).
4. Visualizações (painel ou relatório curto) com insights acionáveis.
5. Recomendação operacional ou política A1 em execução simulada.
6. Seção de **limitações** (RFSIM frente a rede real, viés, lacunas, privacidade).
7. Apresentação oral 20–25 min + breve defesa individual (Aula 06).

## Rubrica (0–10)

| Critério | Pontos |
|----------|--------|
| Aquisição, preparação e qualidade dos dados | 2,0 |
| ETL, organização e reprodutibilidade | 2,0 |
| Definição e interpretação de KPIs/KQIs | 2,0 |
| Análise, visualizações e recomendação operacional | 2,0 |
| Governança, limitações, documentação e apresentação/defesa | 2,0 |

## Temas por grupo (7 × 4)

A turma organiza-se em **7 grupos de 4 pessoas**. Todos usam os **mesmos artefatos KPM**; cada grupo segue um tema em [`temas-grupos.md`](temas-grupos.md) (pergunta, uso dos dados, 2 indicadores, recomendação).

Apoio interno do docente: [`temas-grupos-docente.md`](temas-grupos-docente.md).

| Código | Tema |
|--------|------|
| G1 | Vazão do usuário |
| G2 | Anomalia de carga |
| G3 | Latência / proxy de QoE |
| G4 | Risco de congestionamento |
| G5 | Visão agregada da célula |
| G6 | Economia de energia (intenção simulada) |
| G7 | Política de QoS / steering (candidata) |

## Caso de uso de referência

Declarar no README o código do tema (G1–G7), conforme [`temas-grupos.md`](temas-grupos.md).
