# Briefing — "Latência de rádio como proxy de QoE"

**Projeto Integrador · G3 — Análise de Dados em Redes de Telecom (Módulo 09) · CESAR School**
**Equipe:** Carlos Alberto · Éverton Gomes · Gerson Francisco · Luiz Carlos Santos

Este texto resume, em linguagem simples, o que a apresentação
`apresentacao/seminario-g3-latencia-v2.pdf` mostra. Não é preciso conhecer redes
para entender.

---

## Em uma frase

Investigamos **quando o "tempo de espera" dos dados na rede de celular fica alto o
suficiente para sugerir que o usuário está tendo uma experiência ruim** — e
propusemos uma regra automática para reagir a isso, testada só em simulação.

---

## O que quisemos descobrir

Quando você usa o celular, cada pedacinho de dado leva um tempinho para ir da
antena até o aparelho. Esse tempo é a **latência** (ou "atraso"). Quando ele
sobe muito, vídeos travam, chamadas ficam robóticas, jogos "lagam".

O problema: no nosso laboratório **não existe uma nota de satisfação do usuário**
(aquele "de 1 a 5, como foi sua ligação?"). Então usamos o atraso como um
**substituto** — em inglês, *proxy*. A ideia é: atraso alto costuma andar junto
com usuário insatisfeito, mesmo que a gente não meça a insatisfação diretamente.
Todo o trabalho fala sobre esse substituto, não sobre satisfação medida de fato.

---

## De onde vieram os dados

Um conjunto fixo de **100 medições** feitas num **laboratório simulado** (não é
uma rede de operadora real; não há dados de pessoas). As medições estão divididas
em três momentos:

| Momento | O que é | Quantas medições |
|---|---|---|
| **baseline** | rede tranquila, funcionamento normal | 20 |
| **stress** | rede sob carga pesada, "hora do rush" | 60 |
| **recovery** | logo depois do pico, rede se recuperando | 20 |

Um detalhe importante: em mais da metade das medições de "baseline" e "recovery"
**não havia tráfego nenhum acontecendo** — nesses instantes o atraso aparece como
zero, o que significa "não havia nada para medir", e não "estava perfeito". A
gente separou esses instantes para não distorcer as contas.

---

## Como medimos (os 2 indicadores)

**Indicador 1 — o atraso típico e o atraso nos piores momentos.**
Para cada momento, olhamos:
- o valor **típico** (a mediana — o "meio" das medições);
- o valor nos **piores 5% dos instantes** (o pico recorrente, o "p95").

Resultado, considerando só os instantes com tráfego real:

| Momento | Atraso típico | Piores 5% |
|---|---|---|
| baseline | ~137 | ~204 |
| stress | ~159 | ~191 |
| recovery | ~126 | ~438 |

(valores em microssegundos — a unidade não importa para a leitura; o que importa é
a comparação entre os momentos.)

**Indicador 2 — quanto tempo a rede passou "ruim".**
Escolhemos uma **linha de corte** e medimos a fração de instantes acima dela:

| Momento | % do tempo acima da linha |
|---|---|
| baseline | 25% |
| **stress** | **100%** |
| recovery | 25% |

Ou seja: no pico de carga, **todas** as medições estavam acima da linha. Nos
outros dois momentos, só um quarto — e eram rajadas isoladas, não algo contínuo.

---

## A "linha de corte" e por que confiar nela

A linha separa "rede tranquila" de "rede congestionada". Ela vale ~105 (mesma
unidade de antes). Três checagens mostram que essa escolha não é chute:

1. **Zona de folga.** Entre os valores realmente observados existe um "vão vazio":
   nenhuma medição caiu entre ~95 e ~134. A linha está dentro desse vão. É como um
   interruptor com folga — dá para mexer um pouco na posição sem mudar o
   resultado. Qualquer linha nessa faixa dá a mesma conclusão.
2. **Teste de sensibilidade.** Testamos dezenas de linhas diferentes. Enquanto a
   linha fica na faixa de folga, a conclusão ("só o stress está ruim") não muda.
3. **Teste de estabilidade.** Reembaralhamos os dados milhares de vezes. O
   *número exato* da linha oscila bastante (é pouca amostra), mas a **decisão**
   que ele gera continua a mesma. A gente admite a fragilidade do número e mostra
   que ela não afeta a resposta.

Além disso, exigimos **persistência**: não basta um tropeço isolado. A rede só é
considerada "ruim de verdade" se ficar acima da linha por **5 medições seguidas**.
Isso acontece **56 vezes no stress e nenhuma vez** no baseline ou no recovery.

---

## Comparação com outros métodos

Para não depender de uma única abordagem, comparamos com dois outros modelos:

- **O modelo pronto do laboratório** (feito pelo professor): ele funciona, mas na
  prática detecta o **evento de carga** (vários sinais da rede subindo juntos), e
  não a latência em si. Concorda que o stress é o momento crítico, mas **não
  enxerga** que a rede no "recovery" ainda tem picos altos.
- **EWMA** — um "termômetro com memória curta", que dá mais peso ao que acabou de
  acontecer. Também aponta o stress como crítico e, de bônus, **acende um alerta
  em 55% do "recovery"** — mostrando que a rede não voltou totalmente ao normal,
  algo que os outros dois métodos deixam passar.

Conclusão da comparação: os três métodos concordam no essencial (**agir só no
stress**), o que dá confiança. O método do grupo é o mais adequado à pergunta
(mede latência, em unidade com significado físico), e o EWMA é um bom complemento
para vigiar a recuperação.

---

## O que recomendamos

Durante o pico de carga (stress), acionar uma **política de priorização de
tráfego / investigação da sessão** — na prática, "dar preferência para quem está
sofrendo e olhar o que está acontecendo".

O gatilho combina **duas condições ao mesmo tempo**: (1) a rede está ruim na maior
parte do tempo **e** (2) isso se sustenta por pelo menos 5 medições seguidas. Só o
stress satisfaz as duas.

**Importante:** tudo isso rodou em **modo simulação (ensaio)**. Nenhuma
configuração de rede real foi alterada; nada foi enviado a um equipamento de
verdade.

---

## O que este trabalho NÃO diz

- **Não é uma rede real.** É um laboratório simulado; os números não valem para
  uma operadora comercial.
- **Não é satisfação medida.** Atraso é um substituto; não perguntamos a nenhum
  usuário como foi a experiência.
- **Poucos aparelhos e poucas medições.** As contas são didáticas, não uma
  estatística de campo.
- **O "recovery" não voltou 100% ao normal.** Ainda aparecem picos altos depois do
  pico de carga.
- **A recomendação é um ensaio.** Serve para mostrar o raciocínio, não para ligar
  numa rede em produção.

---

## Conclusão em uma linha

Nos dados analisados, o atraso só indica experiência potencialmente ruim **quando
deixa de ser um pico isolado e passa a dominar o período** — e isso, aqui,
acontece exclusivamente durante o pico de carga.
