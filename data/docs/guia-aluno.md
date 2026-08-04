# Guia do aluno — Módulo 09

**Disciplina:** Análise de Dados aplicada a Redes de Telecomunicações (24 h)  
**Professor:** Jonas Augusto Kunzler · jak@cesar.school  
**Período:** ago/2026

## Calendário oficial

| Aula | Data | Duração | Tema |
|------|------|---------|------|
| 01 | **04/08/2026** | 3h30 | Fontes de dados + apresentação do projeto integrador |
| 02 | **06/08/2026** | 3h30 | Lakes/warehouses + definição preliminar do caso |
| 03 | **08/08/2026** | 5h | EDA/ETL + Checkpoint 1 |
| 04 | **25/08/2026** | 3h30 | KPIs/KQIs + Checkpoint 2 |
| 05 | **27/08/2026** | 3h30 | Capacidade/otimização + checkpoint técnico final |
| 06 | **29/08/2026** | 5h | Apresentações e defesa |

## Avaliação (resumo)

- **50%** Projeto integrador em grupo + apresentação/defesa (Aula 06) — briefing desde o início.
- **30%** Exercícios **individuais** na plataforma `#data`.
- **20%** Engajamento técnico e checkpoints (estudos de caso, participação no projeto, laboratório, defesa individual).

## Artefatos offline (obrigatório para o projeto)

Pacote do docente (`modulo09-artefatos-aluno.zip`) ou, no repositório:

```text
code/datasets/kpm-ue-tp-sample/     ← use este diretório (SQLite/JSONL)
code/datasets/closed-loop-emulate-sample/   ← opcional
```

Índice do que foi enviado: [`PACOTE_ALUNO.md`](PACOTE_ALUNO.md).

## Plataforma de exercícios

https://cesar-activities-cxapa2g7ia-rj.a.run.app/#data/aula01

## Laboratório (opcional — host com Docker)

```bash
cd code/oai-cn-gnb-nonrt-nearrt
./scripts/run_ue_tp_experiment.sh          # regenera artefatos offline
# live (se o docente subir o lab):
# ./scripts/up_e2_lab.sh          # Fase 1
# ./scripts/up_oai_oran_lab.sh    # Fase 2 (não junto com a Fase 1)
```

A avaliação usa prioritariamente os artefatos KPM do pacote. Dificuldades de infraestrutura não determinam a nota quando a trilha offline for seguida.

## Documentos

| Recurso | Caminho |
|---------|---------|
| Pacote / o que enviar | [`PACOTE_ALUNO.md`](PACOTE_ALUNO.md) |
| Briefing do projeto (50%) | [`briefing-projeto.md`](briefing-projeto.md) |
| Temas dos 7 grupos | [`temas-grupos.md`](temas-grupos.md) |
| Briefing da plataforma (30%) | [`briefing-plataforma.md`](briefing-plataforma.md) |
| Alinhamento do laboratório | [`PROJETO_PRATICO.md`](PROJETO_PRATICO.md) |
| Plano de ensino | `plano-ensino-portrait.md` / PDF em `docs/` |
| Índice das fases do lab | `../code/oai-cn-gnb-nonrt-nearrt/docs/FASES_ORAN_LAB.md` |

## Bibliografia básica

PDFs no ambiente da disciplina (`bibliography/basic/`): Tripathi & Shah; Wong et al.; Yanover; Yang et al.
