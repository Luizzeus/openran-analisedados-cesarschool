# Comparação dos dois modelos — G3: Latência / proxy de QoE

**Disciplina:** Análise de Dados em Redes de Telecom (Módulo 09) — CESAR School
**Equipe:** Carlos Alberto · Éverton Gomes · Gerson Francisco · Luiz Carlos Santos
**Documento irmão:** `analise-modelos-alternativos.md` (catálogo completo de alternativas)
**Data:** agosto de 2026

---

## 1. Os dois modelos em foco

| | **Modelo A — do docente** | **Modelo B — do grupo** |
|---|---|---|
| Artefato | `data/code/datasets/kpm-ue-tp-sample/model.json` (+ `decision.json`) | `notebook_g3_latencia.ipynb`, seções 5.2–5.3 e 8 |
| Família | Baseline robusto tipo *z*-score modificado (Iglewicz–Hoaglin) | Limiar empírico por percentil + gatilho de persistência |
| Entrada | 3 features: `DRB.RlcSduDelayDl`, `DRB.UEThpUl`, `RRU.PrbTotUl` | 1 feature: `DRB.RlcSduDelayDl` |
| Treino | 20 amostras do `baseline` | `p75` do `baseline` (20 amostras) |
| Parâmetros | `score_threshold = 3.5`, `mad_floor = 1.0`, `min_anomalous_features = 2`; persistência `window_size = 5` no `decision.json` | `L = 105,5 µs`; gatilho composto `KPI2 > 50 %` **E** ≥ 1 janela de `W = 5` acima de `L` |
| Saída | por amostra: `apply` / `observe` | por fase: `aplicar (dry-run)` / `observar` |
| Objetivo de projeto | anomalia de **carga** multivariada (rApp de treino do lab) | **latência como proxy de QoE** (pergunta do G3) |

> O grupo apelidou o Modelo A de "modelo baseado em média". É mais preciso dizer **baseado em
> mediana + MAD** — uma medida de posição robusta. A intuição do apelido, porém, está certa:
> é um modelo de tendência central do baseline, e é isso que as seções abaixo põem à prova.

---

## 2. Ficha técnica lado a lado

### Modelo A — `robust-baseline-mad`

```
score(x, feature) = |x − mediana_baseline| / max(MAD_baseline, 1.0)
feature anômala   : score > 3.5
decisão "apply"   : nº de features anômalas ≥ 2
persistência      : decision.json aplica window_size = 5 sobre a decisão
```

Como **`MAD = 0` nas três features** (baseline quase constante / ocioso), o
`max(MAD, 1.0)` sempre devolve **1.0** e o `score` vira `|x − mediana|` em **unidade crua**
(µs, kbps, %). O `3.5` deixa de ser "3,5 desvios" e vira "3,5 unidades".

### Modelo B — limiar empírico com zona morta

```
L    = p75(delay do baseline bruto) = 105,5 µs
KPI2_f      = 100 · #{ i ∈ S_f : delay_i > L } / #S_f
gatilho A1  : KPI2_f > 50 %  E  ∃ janela de 5 amostras consecutivas com delay > L
```

Justificativa do `L`: **não** é a estabilidade do percentil (CV ≈ 49 % por bootstrap,
IC95 % ≈ [9,8 ; 174] µs), e sim a **zona morta [101 ; 126) µs** — nenhuma amostra observada
cai aí, então todo `L ∈ [110 ; 120] µs` produz a mesma classificação.

---

## 3. O que cada modelo decide sobre as 100 amostras

| Fase | n | `delay` mediana / p95 bruto (µs) | **Modelo A** — % amostras `apply` | **Modelo B** — `KPI2` (% > L) | Modelo B — janelas W=5 | Decisão de fase (A / B) |
|---|--:|--:|--:|--:|--:|---|
| baseline | 20 | 0 / 186 | **0 %** | 25 % | 0 / 16 | observar / observar |
| stress | 60 | 159 / 191 | **100 %** | 100 % | 56 / 56 | **aplicar** / **aplicar** |
| recovery | 20 | 0 / **394** | **5 %** (1 amostra) | 25 % | 0 / 16 | observar / observar |

**No agregado por fase, os dois concordam:** agir só em `stress`, observar `baseline` e
`recovery`. A diferença está no *porquê*, na *robustez* e no *comportamento de borda*.

### Métricas de acerto (rótulo = fase `stress`)

| | Modelo A | Modelo B |
|---|--:|--:|
| Recall em `stress` | 60/60 = **100 %** | 60/60 = **100 %** |
| Falsos `apply`/`>L` fora de `stress` (nível de amostra) | 1/40 = **2 %** | 20/40 = **50 %** |
| Falso positivo de **decisão de fase** | 0 | 0 (gatilho composto filtra) |
| Cauda de `recovery` (p95 = 394 µs > p95 de `stress`) | **não sinaliza** | não sinaliza (KPI 1 reporta à parte) |

O Modelo A parece "mais preciso" no nível de amostra (2 % vs 50 %), mas isso é enganoso: os
"50 %" do Modelo B são as **rajadas reais** do baseline/recovery (5 amostras ativas de 137–218 µs)
— o gatilho composto (`> 50 %` **e** persistência) as neutraliza na decisão final. O Modelo A
chega ao mesmo lugar por outro caminho: exige 2 das 3 features anômalas, e `thp`/`prb` só se
movem em `stress`.

---

## 4. Onde os dois modelos divergem

### 4.1 O que cada um está medindo

- **Modelo A** só decide `apply` quando **≥ 2 features** saem do baseline. Na prática,
  `DRB.UEThpUl` e `RRU.PrbTotUl` dão saltos grandes em `stress` (PRB 2 % → ~99 %) e é isso
  que carrega a decisão — a feature `delay`, sozinha, marca **45 % do baseline** como anômala.
  **Modelo A ≈ detector de evento de carga.**
- **Modelo B** olha **só o atraso**. É um detector de latência por construção — alinhado com
  a pergunta do G3 ("quando o atraso sugere QoE ruim?").
- **Impacto:** se um cenário elevar o atraso **sem** mexer em PRB/vazão (p.ex. problema de
  agendamento, buffer RLC, retransmissão), o **Modelo A não dispara** (só 1 feature anômala)
  e o **Modelo B dispara**. Para "proxy de QoE", o comportamento do Modelo B é o desejado.

### 4.2 A cauda de `recovery`

`recovery` tem `p95` bruto = **394 µs** e máximo **470 µs** — **acima** do `p95` de `stress`
(191 µs). O notebook (seção 9) trata isso como "recuperação parcial: regime típico voltou, a
cauda não".

- **Modelo A:** classifica `recovery` como "observar" (1 amostra `apply` em 20). Como `thp` e
  `prb` já normalizaram, os dois picos de atraso ficam sozinhos e não atingem "≥ 2 features".
  **O modelo é cego a essa cauda.**
- **Modelo B:** também não "dispara" em `recovery` (sem janela de 5), **mas** o `KPI 1`
  (`mediana` / `p95` sobre `A_f`) **mede e reporta** a cauda: `recovery` = 126 / 438 µs. A
  informação não se perde; ela aparece no indicador certo.
- **Alternativas que enxergariam a cauda** (ver documento irmão): EWMA acende em 55 % de
  `recovery`; Mahalanobis-MCD em 40 %; Isolation Forest (`contamination = 0,2`) em 25 %.

### 4.3 Escala e unidade

- **Modelo A:** o `mad_floor = 1.0` é **cego à unidade**. "1.0" vale 1 µs para o atraso, 1 kbps
  para a vazão e 1 % para o PRB. Se o baseline tivesse qualquer variação real (`MAD > 0`) numa
  feature medida em kbps, `max(MAD, 1.0)` daria `MAD` e o `3.5` seria 3,5 kbps — irrisório,
  tudo vira anomalia. **O modelo depende de o baseline ser quase constante.**
- **Modelo B:** `L` está na mesma unidade do dado (µs) e tem significado físico direto
  ("atraso de rádio acima de ~100 µs"). Comparável a um orçamento 5QI.

### 4.4 Incerteza

- **Modelo A:** não reporta nenhuma. `sample_count = 20`, e pronto.
- **Modelo B:** o grupo **quantificou** a fragilidade do ponto — bootstrap com CV ≈ 49 %,
  IC95 % ≈ [9,8 ; 174] µs — e mostrou que a **decisão** é robusta apesar disso (zona morta).
  Isso é honestidade estatística que o Modelo A não oferece.

### 4.5 Persistência

- **Modelo A:** a decisão do modelo é **por amostra**; a persistência (`window_size = 5`) é
  externa, mora no `decision.json`.
- **Modelo B:** a persistência é **parte do gatilho** (`≥ 1 janela de W = 5`), combinada com
  volume (`KPI2 > 50 %`). Só `stress` satisfaz as duas condições (56/56 janelas); `baseline`
  e `recovery` têm 0/16.
- Nenhum dos dois tem um critério de persistência com **propriedade estatística** (ARL). É aí
  que **EWMA / CUSUM** entram como melhoria (documento irmão, família D).

---

## 5. Matriz de decisão — quando usar qual

| Situação | Modelo recomendado | Motivo |
|---|---|---|
| Pergunta é sobre **latência / QoE** | **B** | mede a variável certa; A dilui no evento de carga |
| Objetivo é **detectar evento de carga** (PRB + vazão + atraso juntos) | **A** | foi para isso que foi treinado; recall 100 %, 2 % de falso |
| Baseline **não é** quase constante (tem variância real) | **B** | o `mad_floor` de A quebra a escala |
| Precisa **auditar / explicar** o limiar a terceiros | **B** | um número em µs com zona morta e IC; A tem escala sem sentido |
| Precisa **enxergar a cauda de `recovery`** | **B** para reportar (KPI 1); **EWMA/MCD** para sinalizar | A é cego a ela |
| Só há os 3 KPIs e nenhum rótulo de fase | **A** | B precisa do `baseline` para o `p75`, mas A também |
| Quer **persistência com ARL controlado** | nenhum — usar **EWMA/CUSUM** | ambos usam janela fixa |

---

## 6. Veredito

**Os dois modelos chegam à mesma decisão operacional neste experimento** (agir só em `stress`),
mas o **Modelo B é o adequado ao problema G3**:

1. mede **latência**, não um evento de carga (Modelo A é, na prática, um detector de PRB/vazão);
2. tem limiar em **unidade física** com significado, comparável a orçamento 5QI;
3. **reporta a incerteza** do ponto e mostra que a decisão é robusta mesmo assim;
4. a cauda de `recovery` **não se perde** — aparece no KPI 1, enquanto o Modelo A a classifica
   como "observar".

O **Modelo A não é inútil**: é um bom detector de evento de carga (recall 100 %, 2 % de falso
no nível de amostra) e serve como **verificação cruzada** — "o modelo do docente concorda que
`stress` é a fase crítica?". Sim. Mas ele **não deve ser o decisor de QoE**.

### Arquitetura combinada sugerida

```
Nível (limiar)        : Modelo B, L ∈ [110;120] µs (zona morta)   [+ âncora 3GPP L=150 µs]
Persistência          : EWMA (λ=0,3, 3σ, params padrão)   ← substitui W=5 fixo
                        (CUSUM é opção, mas exige calibrar µ0=137 µs e h~1–2σ)
Validação do limiar   : árvore de decisão profundidade 1 → corte em 129,9 µs (na zona morta)
Verificação cruzada   : Modelo A + Isolation Forest (contamination≈0,1) — concordância de fase
Cauda de recovery     : reportada por KPI 1 (p95 sobre A_f) e sinalizada por EWMA/Mahalanobis-MCD
```

Detalhamento de cada peça e os números de suporte estão em **`analise-modelos-alternativos.md`**.

---

## 7. Anexo — números de suporte

Gerados por `analise_modelos_alternativos.py` sobre `kpm.jsonl` (100 amostras,
experimento `ue-tp-20260804-174422`), sem modificar os dados.

| Item | Valor |
|---|---|
| `MAD` do baseline (`delay` / `thp` / `prb`) | 0 / 0 / 0 → escala usada = 1,0 (piso) |
| Modelo A — flags de `delay` por fase | 45 % / 100 % / 45 % |
| Modelo A — decisão `apply` por fase | 0 % / 100 % / 5 % |
| Modelo A — recall `stress` / falso `apply` fora de `stress` | 100 % / 2 % |
| Modelo B — `L = p75(baseline bruto)` | 105,5 µs |
| Modelo B — bootstrap de `L` | média 100,3 µs; IC95 % [9,8 ; 174,2]; CV 49 % |
| Modelo B — zona morta observada | [101 ; 126) µs (e [66 ; 95)) |
| Modelo B — `KPI2` por fase | 25 % / 100 % / 25 % |
| Modelo B — janelas `W = 5` acima de `L` | 0 / 56 / 0 |
| `delay` `p95` bruto — stress / recovery | 191 µs / **394 µs** |
| Árvore rasa `delay → stress` — corte | `delay ≤ 129,9 µs` (acurácia 5-fold CV 0,88) |
| Youden-J (só `delay`) | 133,7 µs (TPR 1,00; FPR 0,23); ROC AUC 0,841 |
| EWMA (`λ = 0,3`, 3σ) — alarme por fase | 25 % / 98 % / 55 % |
| Mahalanobis-MCD — anomalia por fase | 30 % / 100 % / 40 % |
| Isolation Forest (`contamination = 0,1`) — por fase | 10 % / 100 % / 10 % |
| Limiar 3GPP `L = 150 µs` — `> L` por fase / janelas W5 | 20 % / 83 % / 15 % · 25/56 |
