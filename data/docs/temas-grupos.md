# Temas do projeto integrador — guia do estudante

Sete grupos de quatro pessoas. **Todos usam os mesmos dados do laboratório.**  
O que muda é a **pergunta**, os **dois indicadores** e a **recomendação** (ou política A1 em simulação).

## Dados que todos recebem

Artefatos KPM do docente (trilha offline), gerados no lab `oai-cn-gnb-nonrt-nearrt`.

| Dado no artefato | Significado simples |
|------------------|---------------------|
| `RRU.PrbTotUl` | Quanto do recurso de rádio (PRB) está em uso no uplink |
| `DRB.RlcSduDelayDl` | Atraso no downlink (latência no enlace de rádio) |
| `DRB.UEThpUl` | Vazão (throughput) do equipamento do usuário no uplink |
| `phase` / `run_id` | Momento do experimento (ex.: normal vs. com carga) |

Pipeline que todo grupo percorre:

```text
ler os dados → limpar e organizar → calcular 2 indicadores → analisar → recomendar (A1 só simulado)
```

Comando de referência (se o ambiente estiver disponível):

```bash
cd code/oai-cn-gnb-nonrt-nearrt
./scripts/run_ue_tp_experiment.sh
```

## Como ler o card do seu grupo

Cada tema abaixo responde a quatro perguntas:

1. **O que investigar?** — a pergunta do grupo  
2. **Como usar os dados?** — o que fazer com PRB, delay e vazão  
3. **Quais 2 indicadores entregar?** — obrigatórios, com fórmula clara no README  
4. **O que recomendar?** — decisão operacional ou política A1 **simulada** (dry-run)

---

### G1 — Vazão do usuário (UE-TP)

1. **O que investigar?**  
   A vazão do UE sobe ou desce junto com o uso de PRB e com o atraso?

2. **Como usar os dados?**  
   - Coloque `DRB.UEThpUl` no centro da análise (série temporal).  
   - Compare com `RRU.PrbTotUl` e `DRB.RlcSduDelayDl` (gráficos e correlação simples).  
   - Separe as fases do experimento (normal × carga), se existirem no arquivo.

3. **Quais 2 indicadores entregar?**  
   - Vazão UL média (e, se útil, percentil 95) por fase.  
   - Utilização média de PRB UL na mesma janela.

4. **O que recomendar?**  
   Se a vazão cair enquanto o PRB estiver alto, propor priorização ou alívio de carga em **política A1 simulada**.

---

### G2 — Detecção de anomalia de carga

1. **O que investigar?**  
   Em que momentos a rede sai do comportamento “normal” de forma sustentada (não um pico isolado)?

2. **Como usar os dados?**  
   - Use as **três** métricas juntas.  
   - Compare cada amostra com um baseline (mediana / MAD do lab ou limiares definidos por vocês).  
   - Conte anomalias por fase e explique falsos alarmes.

3. **Quais 2 indicadores entregar?**  
   - Percentual de amostras anômalas por fase.  
   - Intensidade do desvio (ex.: score médio ou máximo) na fase de carga.

4. **O que recomendar?**  
   Quando a maioria da janela for anômala, gerar `decision` / política candidata tipo “reduzir congestionamento UL” em **dry-run** (fluxo já previsto no lab).

---

### G3 — Latência e qualidade percebida (QoE)

1. **O que investigar?**  
   Quando o atraso de rádio sugere que a experiência do usuário pode estar ruim?

2. **Como usar os dados?**  
   - Foque em `DRB.RlcSduDelayDl` (série e distribuição).  
   - Cruze com `DRB.UEThpUl`: atraso alto com vazão baixa reforça a hipótese de má experiência.  
   - Deixe claro: no lab **não** há nota MOS de aplicativo — o atraso é um **proxy**.

3. **Quais 2 indicadores entregar?**  
   - Atraso RLC (mediana e percentil 95) por fase.  
   - Fração do tempo com atraso acima de um limiar escolhido e justificado.

4. **O que recomendar?**  
   Recomendação operacional (investigar sessão / priorizar tráfego) ou política A1 simulada de prioridade — **sem** afirmar QoE medida de app.

---

### G4 — Risco de congestionamento

1. **O que investigar?**  
   Os dados mostram saturação que justifique um alerta de capacidade?

2. **Como usar os dados?**  
   - Trate `RRU.PrbTotUl` alto como sinal de pressão no rádio.  
   - Confirme com queda ou instabilidade de `DRB.UEThpUl` e/ou subida de `DRB.RlcSduDelayDl`.  
   - Use média móvel para ver tendência, não só um instante.

3. **Quais 2 indicadores entregar?**  
   - Utilização média (ou p95) de PRB UL.  
   - Índice de risco definido por vocês (ex.: combinação PRB alto **e** vazão baixa) — fórmula no README.

4. **O que recomendar?**  
   Alerta de capacidade ou intenção de alívio de carga em política A1 **simulada**.

---

### G5 — Visão agregada da célula

1. **O que investigar?**  
   Como resumir o experimento em indicadores “de célula” e qual o limite disso no lab?

2. **Como usar os dados?**  
   - Agregue por `run_id` e `phase` (média, máximo, percentis) com SQL ou pandas.  
   - Compare fase normal × fase com carga.  
   - Explique que o lab costuma ter **poucos UEs** (muitas vezes um): a agregação é didática, não estatística de campus.

3. **Quais 2 indicadores entregar?**  
   - PRB médio (célula) por fase.  
   - Vazão representativa da célula por fase (média ou soma, justificada).

4. **O que recomendar?**  
   Recomendação de capacidade no nível da célula, deixando explícita a limitação do número de UEs.

---

### G6 — Economia de energia (só intenção)

1. **O que investigar?**  
   Em que trechos a carga está baixa o suficiente para *pensar* em economizar energia — sem desligar nada de verdade?

2. **Como usar os dados?**  
   - Encontre janelas com `RRU.PrbTotUl` baixo e `DRB.UEThpUl` baixo.  
   - Verifique se o atraso permanece aceitável nessas janelas.  
   - O laboratório **não** controla potência de RU: a política é apenas uma **intenção simulada**.

3. **Quais 2 indicadores entregar?**  
   - Fração do tempo em “baixa carga” (limiar de PRB justificado).  
   - Vazão média (ou atraso médio) nessas janelas de baixa carga.

4. **O que recomendar?**  
   Política A1 candidata de economia de energia em **dry-run**, com aviso claro de que não há atuação física na RAN.

---

### G7 — Política de QoS / steering (candidata)

1. **O que investigar?**  
   Diante de degradação, que regra de decisão seria segura para propor uma política de QoS?

2. **Como usar os dados?**  
   - Defina condições do tipo: “se delay > X **ou** (PRB > Y e vazão < Z)”.  
   - Aplique a regra na série temporal e mostre quando ela dispara.  
   - Desenhe o conteúdo da política A1 (escopo UE/QoS, prioridade) — **sem** dizer que o handover ou o path mudaram de fato.

3. **Quais 2 indicadores entregar?**  
   - Tempo (ou % de amostras) em condição de degradação.  
   - Número de vezes em que a regra de política seria acionada.

4. **O que recomendar?**  
   Política A1 simulada (prioridade / steering candidato) + justificativa de por que um humano deveria validar antes de automatizar.

---

## Entregas ao longo do curso

| Aula | O grupo entrega |
|------|-----------------|
| 02 | Tema escolhido + pergunta + como vai usar os dados + ideia dos 2 indicadores |
| 03 | Dados carregados, qualidade checada, primeiros gráficos e indicadores |
| 04 | Dois indicadores bem definidos (fórmula, unidade) + visualizações |
| 05 | Análise final + recomendação ou A1 simulado + limitações |
| 06 | Apresentação (20–25 min) e defesa individual curta |

## Avaliação

Segue o briefing: [`briefing-projeto.md`](briefing-projeto.md).  
Detalhes do laboratório: [`PROJETO_PRATICO.md`](PROJETO_PRATICO.md).
