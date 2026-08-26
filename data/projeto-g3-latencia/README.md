# Projeto Integrador — G3: Latência / proxy de QoE

**Disciplina:** Análise de Dados em Redes de Telecom (Módulo 09) — CESAR School
**Grupo:** 5 (identificação interna da turma) · **Tema oficial:** G3 — Latência / proxy de QoE
**Equipe:** Carlos Alberto · Éverton Gomes · Gerson Francisco · Luiz Carlos Santos

## Pergunta do grupo

Quando o atraso de rádio (`DRB.RlcSduDelayDl`) sugere que a experiência do usuário pode estar ruim?
Usamos o atraso como **proxy de QoE** — o laboratório não produz uma nota MOS de aplicativo real,
então toda conclusão deste projeto é sobre o *proxy*, não sobre QoE medida de fato junto ao usuário.

## Origem dos dados

Artefatos KPM oficiais disponibilizados pelo docente (trilha offline obrigatória), gerados no
laboratório `oai-cn-gnb-nonrt-nearrt` (RFSIM, telemetria sintética de laboratório, sem dados
pessoais), experimento `ue-tp-20260804-174422`:

```
data/code/datasets/kpm-ue-tp-sample/
├── kpm.jsonl        ← bronze (bruto, uma linha por amostra)
├── kpm.sqlite        ← silver (mesmas amostras, tipadas, tabelas runs + kpm_samples)
├── model.json        ← baseline MAD treinado pelo docente
├── decision.json      ← exemplo de decisão/política A1 do pipeline do lab
├── db_summary.json     ← contagem de amostras por fase
└── README.md         ← descrição original do dataset
```

100 amostras no total: `baseline` = 20, `stress` = 60, `recovery` = 20. Métricas usadas:
`DRB.RlcSduDelayDl` (atraso, µs), `DRB.UEThpUl` (vazão UL, kbps), `RRU.PrbTotUl` (uso de PRB UL, %).

## Como reproduzir

1. Guia completo para quem nunca usou Python/Jupyter (instalação do zero):
   guia publicado pelo grupo — [ver artifact](https://claude.ai/code/artifact/4df0c40a-d19e-444e-b2f9-9e18a8cb1fa1).
2. Resumo rápido para quem já tem Python + Jupyter:
   ```
   cd data/projeto-g3-latencia
   jupyter notebook
   ```
   Abrir `notebook_g3_latencia.ipynb` → **Kernel → Restart & Run All**.
3. O notebook lê os dados com um caminho relativo (`../code/datasets/kpm-ue-tp-sample/kpm.jsonl`) —
   não mova o notebook para fora desta pasta sem mover a pasta `code/datasets` junto, mantendo a
   mesma posição relativa.

## Arquitetura de dados (checkpoint Aula 02)

| Camada | Artefato | Papel |
|---|---|---|
| Bronze (bruto) | `kpm.jsonl` | Um registro por linha, schema-on-read |
| Silver (tipado) | `kpm.sqlite` | Consultável via SQL (`runs` + `kpm_samples`) |
| Gold (curado) | Indicadores deste README/notebook, `decision.json` | Pronto para decisão |

Usamos **SQLite/JSONL**, não InfluxDB nem Redis RNIB: a trilha é offline (sem stack near-RT ativa
gerando telemetria contínua, o que justificaria um TSDB) e sem inventário E2 ao vivo (o que
justificaria Redis). Detalhes e consultas de exemplo no notebook, seção 2.1.

## KPIs — definição formal (checkpoint Aula 04)

| Indicador | Fórmula | Granularidade | Fonte |
|---|---|---|---|
| **KPI 1 — Atraso RLC típico** | Mediana e percentil 95 de `DRB.RlcSduDelayDl` (µs) | Por fase (`baseline`/`stress`/`recovery`), todas as amostras | `kpm.jsonl` / `kpm.sqlite` |
| **KPI 2 — Fração de tempo degradado** | % de amostras com `DRB.RlcSduDelayDl` > 105,5 µs (p75 do baseline bruto, n=20) | Por fase, todas as amostras | Mesmo campo; limiar calculado sobre `baseline` |

**Resultado:** KPI 2 = 25,0% em `baseline`, **100,0% em `stress`**, 25,0% em `recovery` — degradação
sustentada (não só picos isolados) durante toda a janela de carga.

O limiar (p75 do baseline bruto) foi testado contra uma alternativa mais "pura" (p75 só de amostras
com tráfego ativo, excluindo `delay=0` ocioso) e mantido por robustez estatística — a alternativa
usa só 9 amostras, instável demais para um percentil. Checagem completa no notebook, seção 5.1.

## Recomendação (checkpoint técnico final — Aula 05)

Durante `stress`, propomos política A1 candidata de **priorização de tráfego / investigação de
sessão**, em execução **simulada (dry-run)** — não há atuação real na RAN, nenhuma configuração foi
alterada. Em `baseline`/`recovery`, a decisão do pipeline é "observar", sem acionar nada. Formato de
decisão espelha `decision.json` do lab; detalhes no notebook, seção 8.

## Limitações

- RFSIM ≠ rede real — resultados não generalizam para uma rede comercial.
- `DRB.RlcSduDelayDl` é um proxy técnico de latência, não uma nota MOS de aplicativo real.
- Poucos UEs no experimento — agregação por fase é didática, não estatística de campus.
- Limiar com trade-off documentado (ver seção 5.1 do notebook).
- Amostras ociosas (delay=0, sem tráfego DL) contam como "sem degradação" no KPI 2 — limitação
  conhecida do indicador, não erro de cálculo.
- Dados sintéticos/simulados de laboratório, sem dados pessoais, uso apenas acadêmico.

## Ética / licença

Telemetria sintética de laboratório RFSIM (OAI), sem dados pessoais, uso exclusivamente acadêmico
neste módulo — conforme `data/code/datasets/kpm-ue-tp-sample/README.md`.

## Progresso do grupo (checkpoints)

| Aula | Data | Status | Entregável |
|---|---|---|---|
| 01 | 04/08 | ✅ Concluída | Tema definido (G3) |
| 02 | 06/08 | ✅ Concluída | Arquitetura (bronze/silver/gold) — notebook seção 2.1 |
| 03 | 08/08 | ✅ Concluída | EDA/qualidade — notebook seções 3 e 3.1 |
| 04 | 25/08 | ✅ Concluída | KPIs formalizados + robustez do limiar — notebook seções 4, 5, 5.1, 5.2 |
| 05 | 27/08 | ✅ Concluída | Recomendação + limitações — notebook seções 8 e 9 |
| 06 | 29/08 | ⏳ Preparado | Apresentação — ver `apresentacao/` |

## Arquivos deste projeto

```
data/projeto-g3-latencia/
├── README.md                 ← este arquivo
└── notebook_g3_latencia.ipynb ← pipeline completo: dados → indicadores → gráficos → recomendação
```
