# Análise de modelos alternativos — G3: Latência / proxy de QoE

**Disciplina:** Análise de Dados em Redes de Telecom (Módulo 09) — CESAR School
**Equipe:** Carlos Alberto · Éverton Gomes · Gerson Francisco · Luiz Carlos Santos
**Documento:** relatório técnico complementar ao `notebook_g3_latencia.ipynb` (seções 5.1–5.3)
**Data:** agosto de 2026

---

## 1. Objetivo e escopo

O pacote de dados do laboratório traz um modelo pronto em
`data/code/datasets/kpm-ue-tp-sample/model.json`. Este documento:

1. descreve **o que esse modelo realmente faz** sobre as 100 amostras KPM do experimento
   `ue-tp-20260804-174422`;
2. enumera **famílias de modelos alternativos** que poderiam substituí-lo ou complementá-lo;
3. roda cada alternativa **sobre os mesmos dados** e reporta o resultado numérico por fase;
4. fecha com uma **recomendação priorizada**.

Todos os números vêm do script `analise_modelos_alternativos.py` (anexo, seção 8), que lê
`kpm.jsonl` sem alterá-lo. A comparação cabeça-a-cabeça entre o modelo do docente e o
modelo do grupo está no documento irmão **`comparacao-modelos.md`**.

Convenção: para a fase `f`, `S_f` = todas as amostras (20 / 60 / 20);
`A_f = { i ∈ S_f : delay_i > 0 }` = amostras com tráfego DL ativo (9 / 60 / 9);
`delay` = `DRB.RlcSduDelayDl` (µs).

---

## 2. O modelo atual, em uma frase — e o seu diagnóstico

`model.json` **não é uma média simples**; é um **baseline robusto tipo _z_-score modificado**
(família Iglewicz–Hoaglin), treinado só no `baseline`:

```
algorithm            : "robust-baseline-mad"
score(x, feature)    = |x − mediana_f| / max(MAD_f, mad_floor=1.0)
feature "anômala"    : score > score_threshold (3.5)
decisão "apply"      : nº de features anômalas ≥ min_anomalous_features (2)
sample_count         : 20   (só o baseline)
```

O grupo já tinha observado (notebook 5.1) que `MAD = 0`. Rodando o modelo sobre os 100 pontos,
o efeito fica explícito:

| Feature | mediana | MAD | escala usada | % de amostras "anômalas" — baseline / stress / recovery |
|---|---:|---:|---:|---|
| `DRB.RlcSduDelayDl` | 0.00 | 0.00 | **1.0** (piso) | **45 % / 100 % / 45 %** |
| `DRB.UEThpUl` | 3.72 | 0.00 | **1.0** (piso) | 0 % / 100 % / 5 % |
| `RRU.PrbTotUl` | 2.00 | 0.00 | **1.0** (piso) | 0 % / 98 % / 5 % |
| **Decisão `apply`** (≥ 2 features) | — | — | — | **0 % / 100 % / 5 %** |

Leitura:

- **O piso `mad_floor = 1.0` destrói a escala.** Com `MAD = 0`, `score = |x − mediana|`
  em unidade **crua** (µs para o atraso, kbps para a vazão). O `score_threshold = 3.5`
  deixa de significar "3,5 desvios robustos" e passa a significar "desvia mais de 3,5 **unidades**
  da mediana". O piso é cego à unidade.
- **O modelo funciona neste dataset por um motivo colateral:** em `stress`, `DRB.UEThpUl` e
  `RRU.PrbTotUl` dão saltos enormes (PRB de 2 % → ~99 %, vazão em outra ordem de grandeza —
  ver `decision.json`), então ficam muito fora de `mediana ± 3,5` e disparam de forma limpa.
  A feature `delay`, sozinha, marca **45 % do baseline** como anômalo — é a regra "≥ 2 de 3"
  que salva a decisão final.
- **Consequência prática:** `model.json` é, de fato, um **detector de evento de carga**
  ("PRB e vazão se moveram juntos"), não um detector de latência. Ele **acerta `stress`
  (recall 100 %)** e quase não gera falso positivo de fase (1 amostra de `recovery`), mas
  **é cego à cauda de `recovery`** — `p95` bruto de `recovery` = **394 µs**, acima do `p95`
  de `stress` (191 µs), e o modelo classifica `recovery` como "observar".
- **Sem persistência embutida.** A lógica de "5 amostras consecutivas" mora no `decision.json`
  (`window_size = 5`), não no modelo.
- **Sem quantificação de incerteza.** `sample_count = 20`; nenhum intervalo de confiança.

É esse conjunto de limitações que as alternativas abaixo tentam resolver.

---

## 3. Critérios de avaliação

Um modelo adequado ao problema G3 precisa:

| # | Critério | Por quê |
|---|---|---|
| C1 | **Foco em latência** como proxy de QoE | é a pergunta do grupo; carga é contexto |
| C2 | **Robusto ao baseline bimodal** (55 % de zeros) | `MAD`/`IQR`/`σ` do baseline bruto degeneram |
| C3 | **Separar pico de degradação sustentada** | espelha `window_size = 5` / política A1 |
| C4 | **Não esconder a degradação de `stress`** | limiares na cauda alta do baseline falham nisso |
| C5 | **Ver a cauda de `recovery`** (recuperação parcial) | ponto que `model.json` perde |
| C6 | **Reportar incerteza** | `p75` do baseline tem CV ≈ 49 % |
| C7 | **Interpretável / reproduzível** | entrega acadêmica, sem caixa-preta como decisor único |
| C8 | **Amostra viável** (n = 100; `A_baseline` = 9) | descarta métodos que exigem centenas de pontos |

---

## 4. Catálogo de alternativas

Cada bloco traz: ideia · resultado **sobre os 100 dados** · prós · contras · veredito.

### A. Consertos do estimador robusto (mínima mudança no modelo do docente)

**A1 — `MAD` sobre `A_baseline` (só amostras ativas).**
`mediana = 137 µs`, `MAD = 47 µs`. Com `|M| > 3,5` (0.6745·|x−med|/MAD), o intervalo normal
vira `[−107 ; 381] µs` → **flags 0 % / 0 % / 10 %**. Captura só os dois picos de `recovery`.
- Prós: conserto de 2 linhas; mantém a família do docente; `MAD ≠ 0`.
- Contras: `A_baseline` tem espalhamento enorme (`{39…218}`), então o intervalo fica largo
  demais e **perde `stress` inteiro** (C4 falha). O `k = 3,5` clássico é inadequado com `n = 9`.
- **Veredito:** melhora a higiene estatística, **insuficiente como detector**.

**A2 — Estimador de escala `Qn` (Rousseeuw–Croux).**
`Qn(A_baseline) = 88,9 µs`. `L = mediana + 3·Qn = 404 µs` → **0 % / 0 % / 5 %**.
`Qn(baseline bruto)` ainda é **0** (mais de metade são zeros — nenhum estimador de escala
escapa disso).
- **Veredito:** `Qn` não colapsa no baseline **ativo**, mas "mediana + k·escala" continua
  largo demais. Mesmo destino de A1.

**A3 — Cercas de Tukey / IQR** (`p75 + 1,5·IQR`). `IQR` do baseline bruto = 0 → degenera
igual ao `MAD` (C2). Só teria sentido sobre `A_baseline`, recaindo em A1.

**A4 — Double MAD (assimétrico).** `MAD` separado à esquerda/direita da mediana. Faz sentido
para a cauda assimétrica de `recovery`, mas exige `A_baseline` (n = 9) → estimativa instável.
Menção metodológica, não entrega.

> **Conclusão da família A:** o baseline **ativo** é disperso demais e o **bruto** é degenerado
> demais para qualquer método "mediana ± k·escala". Isso é, por si só, um argumento a favor do
> **limiar empírico com zona morta** (família B).

### B. Limiar empírico + bootstrap — *a abordagem que o grupo já usa*

`L = p75(baseline bruto) = 105,5 µs` → **KPI 2 = 25 % / 100 % / 25 %**.
Bootstrap (10 000 reamostragens): média 100,3 µs, **IC95 % ≈ [9,8 ; 174,2] µs, CV ≈ 49 %**.
O que sustenta a escolha **não é** a estabilidade do percentil, e sim a **zona morta**: entre
os valores observados há um vão em **[101 ; 126) µs** (e outro em [66 ; 95)). Varredura:

| `L` (µs) | baseline > L | stress > L | recovery > L |
|---:|---:|---:|---:|
| 100 | 25 % | 100 % | 30 % |
| 110 | 25 % | 100 % | 25 % |
| 120 | 25 % | 100 % | 25 % |
| 133 | 25 % | 100 % | 20 % |

- Prós: atende C1, C2, C4; decisão **robusta** ainda que o ponto seja instável; trivial de
  explicar e auditar; já validado no notebook.
- Contras: o valor pontual **não é** estatisticamente estável (C6 exige reportar isso — o
  grupo já reporta); depende de haver uma zona morta (existe aqui; pode não existir em outro
  experimento).
- Complemento natural: **KDE** dos dois modos (ocioso + rajada) apenas para *ilustrar* a
  bimodalidade — não como decisor (n = 9 ativos).
- **Veredito:** **mantém-se como o modelo de limiar.** É o que melhor casa com os critérios.

### C. Teoria de Valores Extremos (EVT) — para a cauda (KPI 1 `p95`)

**Peak-Over-Threshold + Pareto Generalizada (GPD)** ajusta os excessos acima de um limiar e
estima `p95`/`p99` com IC — o método padrão para "atraso de cauda" em redes.
- Contras: exige **dezenas a centenas de excessos**; aqui `A_baseline` = 9, `A_recovery` = 9.
- **Veredito:** citar como "o jeito correto de estimar a cauda **se houvesse amostra**".
  Não é entrega deste dataset.

### D. Detecção de mudança / séries temporais — *substitui a "janela de 5"*

Os dados são ordenados no tempo (`baseline → stress → recovery`) e a política A1 já exige
persistência. Isso é literatura de *change detection*.

**D1 — CUSUM tabular.** Sensível à referência `µ0` e ao limite `h`:
- `µ0 = mediana(baseline bruto) = 0`, `σ ≈ 70 µs`, `k = 0,5σ`, `h = 5σ`: **17 alarmes antes de
  `stress` começar** e 85 % do baseline em alarme — a referência `µ0 = 0` ignora as rajadas
  de até 218 µs do baseline.
- `µ0 = mediana(baseline ativo) = 137 µs`, mesmo `h = 5σ ≈ 348 µs`: cai para **0 % / 0 % / 5 %**
  — agora `h` é grande demais frente ao deslocamento real (mediana de `stress` = 159 µs, só
  ~22 µs acima de `µ0`).
- CUSUM **funcionaria** aqui, mas exige calibrar `µ0` (baseline ativo) **e** reduzir `h` para
  ~1–2σ, dado que o *shift* é modesto. Não é plug-and-play neste dataset.

**D2 — EWMA** (`λ = 0,3`, limite 3σ, `µ0 = mediana(baseline bruto)`). `UCL = 87,8 µs` →
alarmes **25 % / 98 % / 55 %**. Pega `stress` quase inteiro **e** acende em 55 % de `recovery`
— ou seja, **enxerga a cauda de `recovery`** (C5), coisa que `model.json` não faz. Funciona
com os parâmetros clássicos, sem tuning fino.
- **Veredito D1+D2:** **usar EWMA** como mecanismo de persistência (robusto aos parâmetros
  padrão). CUSUM só se houver tempo para calibrar `µ0`/`h`. Ambos melhor fundamentados que a
  janela fixa; atendem C3 e C5.

**D3 — Page–Hinkley** — versão *online* do CUSUM; útil se o enquadramento for "streaming
near-RT". Mesma família de D1.

**D4 — Change-point *offline* (PELT / `ruptures`).** Segmenta a série inteira e devolve os
pontos de quebra; validaria que as quebras coincidem com as transições de fase rotuladas
(20, 80). Requer o pacote `ruptures` (não instalado no ambiente atual); um corte único
ingênuo por diferença de médias cai no idx 89 (dominado pela cauda de `recovery`), não no 20
— ou seja, **precisa de segmentação multi-ponto de verdade**.
- **Veredito:** ótima **figura de validação** para o seminário se `ruptures` for instalado;
  opcional.

### E. Multivariado — usa `delay`, `thp`, `prb` juntos

Treino = `baseline` (n = 20). Anomalia por fase (baseline / stress / recovery):

| Método | baseline | stress | recovery | Observação |
|---|---:|---:|---:|---|
| **Mahalanobis + MCD** (corte χ²₀.₉₇₅) | 30 % | **100 %** | **40 %** | vê a cauda de `recovery`; 30 % de falso no baseline |
| **Isolation Forest** (`contamination=0.1`) | 10 % | **100 %** | 10 % | mais limpo; alta variância com n = 20 |
| Isolation Forest (`contamination=0.2`) | 20 % | 100 % | 25 % | sensível ao hiperparâmetro |
| **LOF** (`k = 10`, novelty) | 40 % | 100 % | 45 % | ruidoso com n pequeno |

- Prós: Mahalanobis-MCD é a **generalização natural do _z_-score** para 3D e é interpretável;
  todos pegam `stress`; MCD e IF≥0.2 **enxergam a cauda de `recovery`**.
- Contras: `n = 20` para estimar uma covariância 3×3 (MCD) é o limite; Isolation Forest / LOF
  têm **alta variância** com essa amostra e dependem de `contamination`/`k`; One-Class SVM e
  LOF **não são recomendados** aqui (hiperparâmetros + n insuficiente).
- **Veredito:** **Isolation Forest** (`contamination ≈ 0,1`) e **Mahalanobis-MCD** valem como
  **verificação cruzada** — "um método caixa-preta e um paramétrico concordam que `stress` é a
  fase crítica e que `recovery` tem resíduo?". **Nunca como decisor único** (C7).

### F. Supervisionado — o grupo **tem os rótulos de fase**

Como cada amostra é rotulada (`baseline`/`stress`/`recovery`), dá para tratar como
**classificação** `delay → P(stress)` e usar isso para **validar o limiar**:

| Modelo | Resultado sobre os 100 dados |
|---|---|
| **Árvore de decisão, profundidade 1** | corte único aprendido: **`delay ≤ 129,9 µs`** → cai **dentro da zona morta**; acurácia 5-fold CV = **0,88** |
| **Limiar ótimo por Youden-J** (só `delay`) | **133,7 µs** (TPR = 1,00; FPR = 0,23); ROC AUC = **0,841** |
| **Regressão logística** (3 features) | ROC AUC in-sample 0,996, **mas** o peso vai quase todo para `PRB` (coef. 0,17) e quase nada para `delay` (0,004) — vira detector de carga, não de latência |

- Prós: a **árvore rasa** encontra sozinha um corte na faixa [130 ; 134) µs → **validação
  independente e visual do `L` do grupo** (C7). Youden-J dá 133,7 µs, coerente com o início
  empírico de `stress`.
- Contras: os rótulos são de **fase experimental**, não de "QoE ruim de verdade" — a
  generalização é ≈ nula (o grupo já diz isso nas Limitações). A logística mostra o risco de
  deixar o modelo escolher a feature: ele abandona a latência.
- **Veredito:** **incluir a árvore rasa + Youden-J como seção de validação do limiar.**
  Barato, alto valor didático. **Não** usar a logística multivariada como decisor (fere C1).

### G. Limiar por orçamento / SLA (3GPP 5QI) — não depende de treino

Para uma afirmação sobre **proxy de QoE**, o critério mais defensável é um **orçamento de
latência de rádio** derivado de norma (3GPP define *Packet Delay Budget* por 5QI; a parcela
de ar/RLC é uma fração disso). O grupo já usa **150 µs** como âncora de sanidade:

| `L` (µs) | origem | baseline / stress / recovery > L | janelas W=5 em `stress` |
|---:|---|---|---:|
| 105,5 | p75 empírico (grupo) | 25 % / 100 % / 25 % | 56/56 |
| **150** | **orçamento de rádio** | 20 % / **83 %** / 15 % | 25/56 |
| 200 | conservador | 5 % / 2 % / 10 % | 0/56 |

`L = 150 µs` **preserva a narrativa** (stress amplamente degradado, baseline/recovery menores);
`L = 200 µs` a quebra.
- **Veredito:** usar como **critério independente que concorda** — fortalece a conclusão sem
  depender da fragilidade do percentil (C6).

---

## 5. Tabela comparativa geral

| Família / método | C1 latência | C2 robusto ao bimodal | C3 persistência | C4 não esconde stress | C5 vê cauda recovery | C6 incerteza | C7 interpretável | C8 n=100 ok | Papel sugerido |
|---|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|---|
| `robust-baseline-mad` (atual) | ✗ (carga) | ✗ (piso) | ✗ (externa) | ✓ | ✗ | ✗ | ~ | ✓ | — (referência) |
| A1/A2 MAD-ativo / Qn | ✓ | ~ | ✗ | ✗ | ~ | ✗ | ✓ | ✓ | descartado |
| **B. Limiar empírico + zona morta** | ✓ | ✓ | ✗ | ✓ | ~ | ✓* | ✓ | ✓ | **limiar principal** |
| C. EVT / GPD | ✓ | ✓ | ✗ | ✓ | ✓ | ✓ | ~ | ✗ | só menção |
| **D2 EWMA** (D1 CUSUM só com tuning) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | **persistência** |
| D4 PELT (`ruptures`) | ✓ | ✓ | ✓ | ✓ | ✓ | ~ | ✓ | ✓ | validação (opcional) |
| E. Isolation Forest / Mahalanobis-MCD | ~ | ✓ | ✗ | ✓ | ✓ | ✗ | ~ | ~ | verificação cruzada |
| **F. Árvore rasa + Youden-J** | ✓ | ✓ | ✗ | ✓ | ✗ | ~ | ✓ | ✓ (validação) | **validação do L** |
| G. Limiar 3GPP/5QI | ✓ | ✓ | ✗ | ✓ | ~ | ✓ | ✓ | ✓ | critério independente |

`*` incerteza **reportada** via bootstrap; o ponto em si é instável.

---

## 6. Recomendação priorizada

1. **Substituir o `model.json` degenerado por dois blocos explícitos:**
   - **Nível:** o limiar empírico do grupo, `L ∈ [110 ; 120] µs` na zona morta, descrito
     formalmente como "limiar do p75 do baseline com IC por bootstrap", **acompanhado da
     âncora 3GPP/5QI (`L = 150 µs`)** como segundo critério que conta a mesma história.
   - **Persistência:** trocar a "janela de 5 fixa" por **EWMA (`λ = 0,3`, 3σ)** — funciona com
     parâmetros padrão e ainda acende na cauda de `recovery`. CUSUM é opção se houver tempo
     para calibrar `µ0` (baseline ativo) e `h` (~1–2σ).
2. **Adicionar seção de validação do limiar** com **árvore de decisão de profundidade 1**
   (`delay → fase`): mostra que o corte aprendido (129,9 µs) e o Youden-J (133,7 µs) caem na
   zona morta — terceira evidência independente de que `L` não é arbitrário.
3. **Rodar Isolation Forest (`contamination ≈ 0,1`) e Mahalanobis-MCD** apenas como
   **verificação cruzada** e reportar a concordância ("caixa-preta e paramétrico apontam
   `stress` como fase crítica e resíduo em `recovery`"), sempre com a ressalva de `n = 20` no
   treino.
4. **Descartar explicitamente, com o porquê** (para o relatório): `média + k·σ` (não robusto,
   sensível à cauda de `recovery`); MAD-ativo / Qn como detector isolado (largos demais);
   One-Class SVM / LOF (hiperparâmetros + n insuficiente); EVT/GPD (amostra pequena);
   logística multivariada como decisor (abandona a latência, fere C1).
5. **`recovery` deixa de ser "só observar":** qualquer modelo sensível à cauda (EWMA,
   Mahalanobis-MCD, IF≥0,2) sinaliza resíduo em `recovery` — registrar como "recuperação
   parcial, cauda ainda acima de `stress`", coerente com a seção 9 do notebook.

---

## 7. Ameaças à validade desta análise

- **`n` minúsculo por fase** (`A_baseline` = `A_recovery` = 9). Percentis, `MAD`, covariância
  3×3 e qualquer ajuste de cauda têm incerteza alta; os números acima são **ilustrativos do
  comportamento dos métodos**, não estimativas de campo.
- **Rótulo = fase de experimento**, não QoE medida. Os resultados supervisionados **validam o
  limiar**, não produzem um classificador de produção.
- **RFSIM ≠ rede real.** Nada aqui generaliza para rede comercial (idem notebook, seção 9).
- **Isolation Forest / LOF variam com a semente.** Rodados com `random_state = 0`; em
  produção, reportar média ± desvio sobre várias sementes.
- **CUSUM/EWMA** dependem da referência `µ0` e da escala `σ`; a escolha de `µ0` sobre o
  baseline **bruto** (0 µs) leva a sobre-alarme — usar a mediana do baseline **ativo**.

---

## 8. Reprodutibilidade

Script: `analise_modelos_alternativos.py` (mesma pasta). Lê
`../code/datasets/kpm-ue-tp-sample/kpm.jsonl` e `model.json`, não escreve nada nos dados.

```
cd data/projeto-g3-latencia
python analise_modelos_alternativos.py
```

Dependências: `numpy`, `pandas`, `scipy`, `scikit-learn`. Opcional: `ruptures` (para D4).
Ambiente testado: numpy 2.5, pandas 3.0, scipy 1.18, scikit-learn 1.9.

---

## 9. Referências

1. Iglewicz, B.; Hoaglin, D. C. *How to Detect and Handle Outliers*. ASQC, 1993. (z-score modificado / MAD)
2. Rousseeuw, P. J.; Croux, C. "Alternatives to the Median Absolute Deviation". *JASA*, 1993. (estimadores Qn/Sn)
3. Page, E. S. "Continuous Inspection Schemes". *Biometrika*, 1954. (CUSUM)
4. Roberts, S. W. "Control Chart Tests Based on Geometric Moving Averages". *Technometrics*, 1959. (EWMA)
5. Killick, R.; Fearnhead, P.; Eckley, I. A. "Optimal Detection of Changepoints (PELT)". *JASA*, 2012.
6. Rousseeuw, P. J.; van Driessen, K. "A Fast Algorithm for the Minimum Covariance Determinant Estimator". *Technometrics*, 1999. (MCD)
7. Liu, F. T.; Ting, K. M.; Zhou, Z.-H. "Isolation Forest". *ICDM*, 2008.
8. Breunig, M. M. et al. "LOF: Identifying Density-Based Local Outliers". *SIGMOD*, 2000.
9. Youden, W. J. "Index for Rating Diagnostic Tests". *Cancer*, 1950.
10. 3GPP TS 23.501, tabela de características de 5QI (*Packet Delay Budget*).
11. Dataset e modelo do laboratório: `data/code/datasets/kpm-ue-tp-sample/{kpm.jsonl,model.json,decision.json}`.
12. `data/projeto-g3-latencia/notebook_g3_latencia.ipynb`, seções 5.1–5.3 e 9.
