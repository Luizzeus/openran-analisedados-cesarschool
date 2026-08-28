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

## KPIs — definição formal (checkpoint Aula 04, validado na Aula 05)

Notação: para a fase `f`, `S_f` = todas as amostras da fase (20 / 60 / 20);
`A_f = { i ∈ S_f : DRB.RlcSduDelayDl_i > 0 }` = amostras com tráfego DL ativo (9 / 60 / 9).

| Indicador | Fórmula | Granularidade | Fonte |
|---|---|---|---|
| **KPI 1 — Atraso RLC típico e de cauda** | `mediana` e `p95` de `DRB.RlcSduDelayDl` (µs) sobre `A_f`; versão bruta sobre `S_f` reportada em paralelo | Por fase (`baseline`/`stress`/`recovery`) | `kpm.jsonl` / `kpm.sqlite`, campo `DRB.RlcSduDelayDl` |
| **KPI 2 — Fração de tempo em degradação** | `KPI2_f = 100 · #{i ∈ S_f : delay_i > L} / #S_f` (%), com `L = 105,5 µs`; versão `KPI2_ativo_f` sobre `A_f` reportada em paralelo | Por fase | Mesmo campo; `L` justificado abaixo |

**Gatilho de degradação sustentada** (usado pela política A1): existe janela de **5 amostras
consecutivas** com `delay_i > L` — espelha `decision.json` (`window_size = 5`, `apply_votes = 5`).

**Valores.** KPI 1 (sobre `A_f`): baseline **137 / 204 µs** · stress **159 / 191 µs** · recovery
**126 / 438 µs**. KPI 2 (sobre `S_f`): **baseline 25,0 % · stress 100,0 % · recovery 25,0 %**.
KPI 2 (sobre `A_f`): baseline **55,6 %** · stress **100,0 %** · recovery **55,6 %**.
Janelas-de-5 acima de `L`: **0 / 56 / 0**. → degradação sustentada só em `stress`.

**Escolha e validação do limiar `L`.** O baseline é bimodal: 55 % das amostras são ociosas
(`delay = 0`) e as 9 ativas valem `{39, 45, 55, 95, 137, 161, 171, 184, 218} µs`; a fase `stress`
começa em 133,7 µs. Existe uma **faixa vazia entre 95 e 134 µs — qualquer `L` nesse intervalo gera
o mesmo KPI 2**, então a decisão é robusta ainda que o ponto de percentil não seja (o p75 do
baseline bruto tem IC95 % por bootstrap ≈ [10; 174] µs, CV ≈ 48 %). Rejeitamos o p75 do baseline
só-ativo (171 µs) e limiares da cauda alta do baseline: caem *dentro* do aglomerado de `stress`
(mediana 159 µs) e derrubam o KPI 2 de `stress` para ~22 %, escondendo a degradação. `mediana +
k·MAD` do baseline bruto degenera para 0 (MAD = 0). Âncora de sanidade: um limiar absoluto de
150 µs mantém a mesma história (`stress` 83 %, `baseline` 20 %). Sweep completo no notebook,
seção 5.2; fórmula final na seção 5.3.

## Recomendação (checkpoint técnico final — Aula 05)

Durante `stress`, propomos política A1 candidata de **priorização de tráfego / investigação de
sessão**, em execução **simulada (dry-run)** — não há atuação real na RAN, nenhuma configuração foi
alterada. O gatilho combina **duas condições necessárias**: (1) `KPI2_f > 50 %` **e** (2) pelo menos
uma janela de 5 amostras consecutivas acima de `L` (persistência), espelhando `decision.json`
(`window_size = 5`, `apply_votes = 5`). Só `stress` satisfaz as duas: 56/56 janelas disparariam;
`baseline` e `recovery` têm 0/16, então a decisão do pipeline nessas fases é "observar". Detalhes
no notebook, seção 8.

## Limitações

- **RFSIM ≠ rede real** — resultados não generalizam para uma rede comercial.
- **`DRB.RlcSduDelayDl` é proxy técnico de latência**, não uma nota MOS de aplicativo real.
- **Poucos UEs no experimento** — agregação por fase é didática, não estatística de campus.
- **Ponto de limiar numericamente instável, mas decisão robusta.** O p75 do baseline bruto tem
  IC95 % por bootstrap ≈ [10; 174] µs (CV ≈ 48 %); o KPI 2 não é sensível a isso porque `L` cai
  na faixa sem amostras 95–134 µs. Trocar o critério por um limiar da cauda alta do baseline
  mudaria as conclusões — ver seção 5.2 do notebook.
- **`baseline` 25 % não é "ruído".** São 5 amostras ativas reais do baseline (137–218 µs) já no
  patamar de carga: mesmo em repouso, 1 em cada 4 rajadas do UE vê atraso tipo-`stress`. O
  `KPI2_ativo` (55,6 %) torna isso explícito.
- **`recovery` não voltou totalmente ao normal.** A cauda de `recovery` traz 390 µs e 470 µs,
  acima do pico de `stress` (265 µs) — o p95 bruto de `recovery` (394 µs) reflete essa
  recuperação parcial na janela observada.
- **Amostras ociosas (`delay = 0`) contam como "sem degradação" no KPI 2 sobre `S_f`** — por
  isso reportamos também `KPI2_ativo`. Se a fração ociosa subisse acima de 75 %, o p75 bruto
  colapsaria para 0; usar `L = 105,5 µs` como constante fixa evita esse efeito.
- **Política A1 é simulada (dry-run)** — nenhuma política enviada a um RIC real, nenhuma config
  de rede alterada; o gatilho exige volume **e** persistência para não recomendar atuação com
  base em pico isolado.
- **Dados sintéticos/simulados de laboratório**, sem dados pessoais, uso apenas acadêmico.

## Ética / licença

Telemetria sintética de laboratório RFSIM (OAI), sem dados pessoais, uso exclusivamente acadêmico
neste módulo — conforme `data/code/datasets/kpm-ue-tp-sample/README.md`.

## Progresso do grupo (checkpoints)

| Aula | Data | Status | Entregável |
|---|---|---|---|
| 01 | 04/08 | ✅ Concluída | Tema definido (G3) |
| 02 | 06/08 | ✅ Concluída | Arquitetura (bronze/silver/gold) — notebook seção 2.1 |
| 03 | 08/08 | ✅ Concluída | EDA/qualidade — notebook seções 3 e 3.1 |
| 04 | 25/08 | ✅ Concluída | KPIs formalizados + robustez do limiar — notebook seções 4, 5, 5.1 |
| 05 | 27/08 | ✅ Concluída | Limiar validado (sensibilidade 5.2) + fórmula final (5.3) + recomendação/A1 com persistência (8) + limitações (9) |
| 06 | 29/08 | ✅ Preparado | Apresentação do seminário — `apresentacao/seminario-g3-latencia.pdf` (16 slides) |
| 06 (final) | 29/08 | ✅ Concluída | Apresentação final com modelo comparativo (EWMA + referência ao `robust-baseline-mad`) — `apresentacao/seminario-g3-latencia-v2.pdf` (18 slides) |

## Arquivos deste projeto

```
data/projeto-g3-latencia/
├── README.md                       ← este arquivo
├── notebook_g3_latencia.ipynb      ← pipeline completo: dados → indicadores → gráficos → recomendação
├── analise-modelos-alternativos.md ← catálogo de modelos que poderiam substituir o model.json
├── comparacao-modelos.md           ← modelo do docente (robust-baseline-mad) × modelo do grupo
├── analise_modelos_alternativos.py ← script que gera os números dos dois .md acima
└── apresentacao/
    ├── gerar_apresentacao.py        ← gera figuras + PDF (16 slides) a partir do mesmo dataset
    ├── gerar_apresentacao_v2.py     ← versão final: + modelo comparativo EWMA (2 gráficos e texto novos)
    ├── seminario-g3-latencia.pdf    ← 16 slides do seminário (imagens, gráficos, explicações)
    ├── seminario-g3-latencia-v2.pdf ← 18 slides: idem + EWMA como gatilho de persistência × janela fixa
    └── figuras/                     ← 14 PNGs (gráficos e diagramas) usados nos PDFs
```

Para regenerar a apresentação: `cd apresentacao && python gerar_apresentacao_v2.py`
(usa `pandas`, `numpy`, `scipy`, `matplotlib`, `reportlab`; fontes Segoe UI do Windows).
O `gerar_apresentacao_v2.py` também lê `model.json` para traçar o `robust-baseline-mad` do docente
no gráfico comparativo por fase.
