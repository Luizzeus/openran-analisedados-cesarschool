from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
from reportlab.graphics.charts.barcharts import VerticalBarChart
from reportlab.graphics.charts.lineplots import LinePlot
from reportlab.graphics.charts.textlabels import Label
from reportlab.graphics.shapes import Drawing, Line, Rect, String
from reportlab.lib import colors
from reportlab.lib.colors import HexColor
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    HRFlowable,
    KeepTogether,
    PageBreak,
    PageTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
DATASET = ROOT / "data/code/datasets/kpm-ue-tp-sample/kpm.jsonl"
MODEL = ROOT / "data/code/datasets/kpm-ue-tp-sample/model.json"
DECISION = ROOT / "data/code/datasets/kpm-ue-tp-sample/decision.json"
OUTPUT = ROOT / "output/pdf/relatorio_laboratorio_g3_latencia.pdf"

NAVY = HexColor("#102A43")
BLUE = HexColor("#1769AA")
CYAN = HexColor("#00A6A6")
RED = HexColor("#D64545")
GREEN = HexColor("#2E7D32")
ORANGE = HexColor("#F59E0B")
LIGHT = HexColor("#EEF4F8")
MID = HexColor("#BCCCDC")
INK = HexColor("#243B53")
MUTED = HexColor("#627D98")


def load_data() -> pd.DataFrame:
    rows = [json.loads(line) for line in DATASET.read_text(encoding="utf-8").splitlines() if line.strip()]
    raw = pd.json_normalize(rows)
    df = raw.rename(columns={
        "metrics.DRB.RlcSduDelayDl": "delay",
        "metrics.DRB.UEThpUl": "thp",
        "metrics.RRU.PrbTotUl": "prb",
    })[["run_id", "phase", "sample_index", "delay", "thp", "prb", "ingested_at"]]
    order = ["baseline", "stress", "recovery"]
    df["phase"] = pd.Categorical(df["phase"], categories=order, ordered=True)
    return df.sort_values(["phase", "sample_index"]).reset_index(drop=True)


DF = load_data()
PHASES = ["baseline", "stress", "recovery"]
PHASE_LABELS = {"baseline": "Baseline", "stress": "Stress", "recovery": "Recovery"}
L = float(np.percentile(DF.loc[DF.phase == "baseline", "delay"], 75))
DF["above"] = DF.delay > L


def p95(x):
    return float(np.percentile(x, 95))


def stats(active=False):
    x = DF.loc[DF.delay > 0] if active else DF
    return x.groupby("phase", observed=True).agg(
        n=("delay", "size"), mediana=("delay", "median"), p95=("delay", p95),
        media=("delay", "mean"), thp_mediana=("thp", "median"), prb_media=("prb", "mean")
    )


ALL = stats(False)
ACTIVE = stats(True)
KPI2 = DF.groupby("phase", observed=True).above.mean() * 100
KPI2_ACTIVE = DF.loc[DF.delay > 0].groupby("phase", observed=True).above.mean() * 100


def windows(phase, threshold=L, w=5):
    a = DF.loc[DF.phase == phase, "delay"].to_numpy() > threshold
    return sum(bool(a[i:i+w].all()) for i in range(len(a) - w + 1))


def fmt(x, digits=1):
    return f"{x:,.{digits}f}".replace(",", "X").replace(".", ",").replace("X", ".")


styles = getSampleStyleSheet()
styles.add(ParagraphStyle(name="CoverTitle", fontName="Helvetica-Bold", fontSize=25, leading=29, textColor=colors.white, alignment=TA_LEFT, spaceAfter=14))
styles.add(ParagraphStyle(name="CoverSub", fontName="Helvetica", fontSize=12, leading=17, textColor=HexColor("#D9EAF4")))
styles.add(ParagraphStyle(name="H1x", fontName="Helvetica-Bold", fontSize=17, leading=21, textColor=NAVY, spaceBefore=5, spaceAfter=9))
styles.add(ParagraphStyle(name="H2x", fontName="Helvetica-Bold", fontSize=12, leading=15, textColor=BLUE, spaceBefore=8, spaceAfter=5))
styles.add(ParagraphStyle(name="Bodyx", fontName="Helvetica", fontSize=9.2, leading=13.2, textColor=INK, alignment=TA_JUSTIFY, spaceAfter=6))
styles.add(ParagraphStyle(name="Smallx", fontName="Helvetica", fontSize=7.6, leading=10.2, textColor=MUTED, spaceAfter=4))
styles.add(ParagraphStyle(name="Callout", fontName="Helvetica-Bold", fontSize=10.5, leading=14, textColor=NAVY, backColor=LIGHT, borderColor=CYAN, borderWidth=1, borderPadding=9, spaceBefore=6, spaceAfter=9))
styles.add(ParagraphStyle(name="Caption", fontName="Helvetica-Oblique", fontSize=7.5, leading=10, textColor=MUTED, alignment=TA_CENTER, spaceBefore=3, spaceAfter=7))
styles.add(ParagraphStyle(name="TableHead", fontName="Helvetica-Bold", fontSize=7.8, leading=9.5, textColor=colors.white, alignment=TA_CENTER))
styles.add(ParagraphStyle(name="TableCell", fontName="Helvetica", fontSize=7.6, leading=9.5, textColor=INK, alignment=TA_CENTER))
styles.add(ParagraphStyle(name="Bulletx", parent=styles["Bodyx"], leftIndent=12, firstLineIndent=-7, bulletIndent=0, spaceAfter=3))


def P(text, style="Bodyx"):
    return Paragraph(text, styles[style])


def bullet(text):
    return Paragraph("• " + text, styles["Bulletx"])


def table(rows, widths=None, aligns=None):
    cooked = []
    for ridx, row in enumerate(rows):
        cooked.append([Paragraph(str(v), styles["TableHead" if ridx == 0 else "TableCell"]) for v in row])
    t = Table(cooked, colWidths=widths, repeatRows=1, hAlign="CENTER")
    cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY), ("GRID", (0, 0), (-1, -1), 0.35, MID),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    for i in range(1, len(rows)):
        cmds.append(("BACKGROUND", (0, i), (-1, i), colors.white if i % 2 else LIGHT))
    if aligns:
        for col, align in enumerate(aligns):
            cmds.append(("ALIGN", (col, 1), (col, -1), align))
    t.setStyle(TableStyle(cmds))
    return t


def add_title(story, title, subtitle=None):
    story += [P(title, "H1x"), HRFlowable(width="100%", thickness=1, color=CYAN), Spacer(1, 5)]
    if subtitle:
        story.append(P(subtitle, "Smallx"))


def line_chart():
    d = Drawing(480, 225)
    lp = LinePlot()
    lp.x, lp.y, lp.width, lp.height = 45, 35, 405, 160
    lp.data = [list(zip(range(len(DF.loc[DF.phase == p])), DF.loc[DF.phase == p, "delay"])) for p in PHASES]
    lp.lines[0].strokeColor, lp.lines[1].strokeColor, lp.lines[2].strokeColor = BLUE, RED, GREEN
    for i in range(3):
        lp.lines[i].strokeWidth = 1.5
    lp.xValueAxis.valueMin, lp.xValueAxis.valueMax, lp.xValueAxis.valueStep = 0, 60, 10
    lp.yValueAxis.valueMin, lp.yValueAxis.valueMax, lp.yValueAxis.valueStep = 0, 500, 100
    lp.xValueAxis.labelTextFormat = "%d"
    lp.yValueAxis.labelTextFormat = "%d"
    d.add(lp)
    y = 35 + 160 * L / 500
    d.add(Line(45, y, 450, y, strokeColor=ORANGE, strokeWidth=1, strokeDashArray=[4, 3]))
    d.add(String(451, y-2, f"L={L:.1f} us", fontSize=7, fillColor=ORANGE))
    d.add(String(220, 8, "Índice da amostra dentro da fase", fontSize=8, fillColor=INK))
    d.add(String(5, 207, "Atraso RLC DL (us)", fontSize=8, fillColor=INK))
    for x, c, name in [(245, BLUE, "Baseline"), (315, RED, "Stress"), (375, GREEN, "Recovery")]:
        d.add(Line(x, 212, x+18, 212, strokeColor=c, strokeWidth=2)); d.add(String(x+22, 208, name, fontSize=7, fillColor=INK))
    return d


def bar_chart(values, title, max_y=100):
    d = Drawing(480, 220)
    bc = VerticalBarChart()
    bc.x, bc.y, bc.width, bc.height = 55, 35, 390, 145
    bc.data = [values]
    bc.categoryAxis.categoryNames = ["Baseline", "Stress", "Recovery"]
    bc.valueAxis.valueMin, bc.valueAxis.valueMax = 0, max_y
    bc.valueAxis.valueStep = max_y / 5
    bc.bars[0].fillColor = BLUE
    bc.bars[0].strokeColor = NAVY
    bc.barLabelFormat = lambda x: f"{x:.1f}%" if max_y == 100 else f"{x:.0f}"
    bc.barLabels.nudge = 7
    bc.barLabels.fontSize = 8
    d.add(bc)
    d.add(String(55, 200, title, fontName="Helvetica-Bold", fontSize=10, fillColor=NAVY))
    return d


def sensitivity_chart(thresholds):
    d = Drawing(480, 230)
    lp = LinePlot(); lp.x, lp.y, lp.width, lp.height = 48, 38, 398, 150
    lp.data = [list(zip(thresholds, [100*np.mean(DF.loc[DF.phase == p, "delay"].to_numpy() > t) for t in thresholds])) for p in PHASES]
    for i, c in enumerate([BLUE, RED, GREEN]):
        lp.lines[i].strokeColor = c; lp.lines[i].strokeWidth = 1.8
    lp.xValueAxis.valueMin, lp.xValueAxis.valueMax, lp.xValueAxis.valueStep = min(thresholds), max(thresholds), 25
    lp.yValueAxis.valueMin, lp.yValueAxis.valueMax, lp.yValueAxis.valueStep = 0, 100, 20
    d.add(lp)
    d.add(String(200, 9, "Limiar L (us)", fontSize=8, fillColor=INK))
    d.add(String(5, 205, "% de amostras acima de L", fontSize=8, fillColor=INK))
    for x, c, name in [(240, BLUE, "Baseline"), (310, RED, "Stress"), (370, GREEN, "Recovery")]:
        d.add(Line(x, 210, x+18, 210, strokeColor=c, strokeWidth=2)); d.add(String(x+22, 206, name, fontSize=7, fillColor=INK))
    return d


def header_footer(canvas, doc):
    canvas.saveState()
    if doc.page > 1:
        canvas.setStrokeColor(MID); canvas.line(1.7*cm, A4[1]-1.35*cm, A4[0]-1.7*cm, A4[1]-1.35*cm)
        canvas.setFont("Helvetica", 7.5); canvas.setFillColor(MUTED)
        canvas.drawString(1.7*cm, A4[1]-1.05*cm, "CESAR School | Análise de Dados em Redes de Telecom | G3 - Latência")
        canvas.drawRightString(A4[0]-1.7*cm, 0.9*cm, f"Página {doc.page}")
    canvas.restoreState()


class ReportDoc(BaseDocTemplate):
    def __init__(self, filename):
        super().__init__(filename, pagesize=A4, rightMargin=1.65*cm, leftMargin=1.65*cm, topMargin=1.65*cm, bottomMargin=1.45*cm,
                         title="Relatório do Laboratório - G3 Latência / proxy de QoE", author="Grupo 3")
        frame = Frame(self.leftMargin, self.bottomMargin, self.width, self.height, id="normal")
        self.addPageTemplates(PageTemplate(id="all", frames=frame, onPage=header_footer))


def build():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    story = []
    # Capa
    cover = Drawing(480, 655)
    cover.add(Rect(0, 0, 480, 655, fillColor=NAVY, strokeColor=NAVY))
    cover.add(Rect(0, 0, 480, 105, fillColor=CYAN, strokeColor=CYAN))
    cover.add(String(38, 575, "PROJETO INTEGRADOR", fontName="Helvetica-Bold", fontSize=11, fillColor=HexColor("#7FDBDA")))
    cover.add(String(38, 515, "Laboratório G3", fontName="Helvetica-Bold", fontSize=28, fillColor=colors.white))
    cover.add(String(38, 478, "Latência e qualidade percebida", fontName="Helvetica-Bold", fontSize=22, fillColor=colors.white))
    cover.add(String(38, 447, "DRB.RlcSduDelayDl como proxy de QoE", fontName="Helvetica", fontSize=14, fillColor=HexColor("#D9EAF4")))
    cover.add(Line(38, 425, 440, 425, strokeColor=CYAN, strokeWidth=2))
    cover.add(String(38, 375, "Disciplina: Análise de Dados em Redes de Telecom", fontSize=10, fillColor=colors.white))
    cover.add(String(38, 351, "Equipe: Carlos Alberto | Éverton Gomes | Gerson Francisco | Luiz Carlos Santos", fontSize=9, fillColor=colors.white))
    cover.add(String(38, 327, "CESAR School | Agosto de 2026", fontSize=10, fillColor=colors.white))
    cover.add(String(38, 65, "100 amostras KPM | baseline, stress e recovery | análise offline reproduzível", fontName="Helvetica-Bold", fontSize=10, fillColor=NAVY))
    cover.add(String(38, 39, "Relatório técnico com simulações, análise de sensibilidade e política A1 em dry-run", fontSize=8.5, fillColor=NAVY))
    story += [cover, PageBreak()]

    add_title(story, "Resumo executivo")
    story.append(P("O laboratório investigou quando o atraso de rádio em downlink sugere degradação da experiência do usuário. Foram analisadas 100 amostras KPM sintéticas do experimento <b>ue-tp-20260804-174422</b>, distribuídas em baseline (20), stress (60) e recovery (20). O atraso RLC é tratado estritamente como <b>proxy técnico de QoE</b>; não há MOS, telemetria de aplicação ou medição ponta a ponta."))
    story.append(P(f"O limiar analítico foi fixado em <b>L = {fmt(L)} us</b>, correspondente ao p75 do baseline bruto. Embora esse percentil seja instável devido ao tamanho reduzido e à bimodalidade do baseline, L está numa faixa sem observações entre 95 e 133,7 us. Assim, qualquer limiar nessa faixa preserva a classificação das amostras, tornando a decisão operacional mais robusta que o valor pontual do percentil."))
    story.append(P(f"Na fase stress, a mediana/p95 do atraso com tráfego ativo foi <b>{fmt(ACTIVE.loc['stress','mediana'],0)}/{fmt(ACTIVE.loc['stress','p95'],0)} us</b>, e <b>{fmt(KPI2['stress'])}%</b> das amostras excederam L. Todas as 56 janelas possíveis de cinco amostras permaneceram acima do limiar. Baseline e recovery tiveram {fmt(KPI2['baseline'])}% e {fmt(KPI2['recovery'])}% de excedência, mas nenhuma janela sustentada de cinco, impedindo atuação por picos isolados."))
    story.append(P("<b>Conclusão:</b> os dados sustentam uma condição de degradação persistente apenas em stress. Recomenda-se investigar a sessão, o agendamento de rádio e a relação entre atraso, PRB e vazão; como resposta candidata, simular prioridade de tráfego via política A1, sempre em dry-run e com validação humana. A recovery apresenta dois picos severos (390 e 470 us), portanto recuperou o regime típico, mas não a cauda." , "Callout"))
    story.append(P("Principais resultados", "H2x"))
    rows = [["Fase", "n", "Mediana ativa (us)", "p95 ativo (us)", "% > L (todas)", "Janelas W=5"]]
    for p in PHASES:
        denom = len(DF.loc[DF.phase == p]) - 4
        rows.append([PHASE_LABELS[p], int(ALL.loc[p,"n"]), fmt(ACTIVE.loc[p,"mediana"],0), fmt(ACTIVE.loc[p,"p95"],0), fmt(KPI2[p])+"%", f"{windows(p)}/{denom}"])
    story += [table(rows, [2.3*cm,1.2*cm,3.1*cm,2.8*cm,2.8*cm,2.7*cm]), PageBreak()]

    add_title(story, "1. Enunciado, objetivo e critérios de aceite")
    story.append(P("O tema oficial G3 pergunta: <b>quando o atraso de rádio sugere que a experiência do usuário pode estar ruim?</b> O enunciado exige foco em DRB.RlcSduDelayDl, cruzamento com DRB.UEThpUl, dois indicadores formais, visualizações, recomendação operacional ou política A1 simulada e limitações explícitas."))
    story.append(P("Objetivo geral", "H2x")); story.append(P("Caracterizar o atraso RLC por fase, separar picos de degradação sustentada, avaliar a estabilidade do limiar e produzir uma recomendação operacional reproduzível sem extrapolar o alcance dos dados."))
    story.append(P("Critérios de aceite adotados", "H2x"))
    for x in [
        "Aquisição e qualidade: contagens por fase, tipos, nulos, duplicidades, zeros e coerência temporal.",
        "ETL/reprodutibilidade: JSONL como bronze; DataFrame/SQLite como silver; indicadores, figuras e decisão como gold.",
        "Indicadores: fórmula, unidade, fonte, granularidade e interpretação explícitas.",
        "Análise: comparação baseline-stress-recovery, cruzamento com vazão e análise de sensibilidade.",
        "Governança: dados sintéticos, política em dry-run, limitações e ausência de MOS declaradas.",
    ]: story.append(bullet(x))
    story.append(P("Hipóteses de trabalho", "H2x"))
    story.append(table([
        ["Hipótese", "Teste", "Critério de interpretação"],
        ["H1: stress eleva o atraso", "Mediana/p95 e % > L por fase", "Efeito amplo e persistente, não só máximo"],
        ["H2: atraso alto com vazão baixa reforça degradação", "Correlação e médias condicionais", "Evidência associativa; sem causalidade"],
        ["H3: recovery normaliza", "Estatística típica e cauda", "Mediana baixa não basta se p95 permanecer alto"],
    ], [4.1*cm,5.0*cm,7.0*cm], ["LEFT","LEFT","LEFT"]))
    story.append(PageBreak())

    add_title(story, "2. Dados, arquitetura e execução do laboratório")
    story.append(P("A fonte é o pacote KPM oficial do docente, gerado em RFSIM no laboratório OAI. Cada linha de kpm.jsonl representa uma amostra e contém run_id, fase, índice, horário de ingestão e as três métricas usadas. O laboratório foi reexecutado offline a partir do artefato versionado; nenhuma configuração de RAN foi alterada."))
    story.append(table([
        ["Camada", "Artefato", "Uso no laboratório"],
        ["Bronze", "kpm.jsonl", "Registro bruto, schema-on-read, 100 linhas"],
        ["Silver", "kpm.sqlite / DataFrame tipado", "Ordenação, qualidade, consultas e agregações"],
        ["Gold", "KPIs, gráficos e decisão", "Interpretação e política candidata em dry-run"],
    ], [2.5*cm,5.0*cm,8.6*cm], ["LEFT","LEFT","LEFT"]))
    story.append(P("Inventário das variáveis", "H2x"))
    story.append(table([
        ["Variável", "Unidade", "Papel"],
        ["DRB.RlcSduDelayDl", "us", "Atraso RLC DL; KPI de integridade e proxy KQI/QoE"],
        ["DRB.UEThpUl", "kbps", "Vazão UL do UE; variável de contexto"],
        ["RRU.PrbTotUl", "%", "Uso de PRB UL; contexto de carga"],
        ["phase / sample_index", "categoria / índice", "Granularidade e ordenação do experimento"],
    ], [5.0*cm,2.4*cm,8.7*cm], ["LEFT","CENTER","LEFT"]))
    story.append(P("Procedimento executado", "H2x"))
    for x in ["Leitura e normalização do JSONL; seleção e renomeação das métricas.", "Ordenação por fase e sample_index; conferência das contagens e integridade.", "Separação entre população completa S_f e amostras ativas A_f (delay > 0).", "Cálculo de KPI 1, KPI 2, persistência, correlações e cenários alternativos.", "Geração automática deste PDF a partir do mesmo dataset."]: story.append(bullet(x))
    story.append(PageBreak())

    add_title(story, "3. Qualidade dos dados e decisões de tratamento")
    nulls = int(DF[["delay","thp","prb"]].isna().sum().sum()); dups = int(DF.duplicated(["run_id","phase","sample_index"]).sum())
    story.append(P(f"Foram carregadas <b>{len(DF)} amostras</b>. A verificação encontrou <b>{nulls} valores nulos</b> nas métricas e <b>{dups} duplicidades</b> na chave run_id + phase + sample_index. As fases contêm 20/60/20 amostras, conforme o pacote do docente."))
    idle_rows = [["Fase", "Amostras", "Delay = 0", "% ociosas", "Amostras ativas"]]
    for p in PHASES:
        g=DF.loc[DF.phase==p]; n0=int((g.delay==0).sum())
        idle_rows.append([PHASE_LABELS[p],len(g),n0,fmt(100*n0/len(g))+"%",len(g)-n0])
    story.append(table(idle_rows,[3.0*cm,2.5*cm,2.5*cm,2.5*cm,3.0*cm]))
    story.append(P("Os zeros não foram removidos indiscriminadamente. Em baseline e recovery, 55% das observações têm delay = 0 e vazão residual, compatível com ausência de tráfego DL mensurável naquela amostra. Por isso o relatório apresenta duas visões complementares:"))
    story.append(bullet("População completa S_f: adequada para a fração de tempo do experimento e para o gatilho operacional."))
    story.append(bullet("População ativa A_f: adequada para descrever a latência quando existe tráfego DL, evitando que os zeros ocultem a distribuição efetiva."))
    story.append(P("Essa decisão evita dois erros opostos: excluir os zeros e inflar artificialmente a incidência temporal, ou mantê-los como latência real e reduzir artificialmente mediana/p95 do tráfego ativo." , "Callout"))
    story.append(P("Riscos de validade dos dados", "H2x"))
    for x in ["Amostra pequena nas fases baseline e recovery, especialmente A_f com n=9.", "Baseline bimodal, com massa em zero; medidas de posição dependem do tratamento de ociosidade.", "RFSIM e poucos UEs não representam dispersão, interferência e mobilidade de uma rede comercial.", "Não há periodicidade de coleta documentada no relatório; janelas são expressas em amostras, não em segundos."]: story.append(bullet(x))
    story.append(PageBreak())

    add_title(story, "4. Definição formal dos indicadores")
    story.append(P("Considere S_f como todas as amostras da fase f e A_f = {i em S_f: delay_i > 0}. O limiar oficial é L = p75 do baseline bruto = 105,5 us. O operador de excedência é estrito: delay_i > L."))
    story.append(P("KPI 1 - atraso RLC típico e de cauda", "H2x"))
    story.append(P("Para cada fase: <b>KPI1_f = [mediana(delay_i), p95(delay_i)]</b>. A mediana representa comportamento típico com robustez a picos; o p95 evidencia a cauda. A visão primária é calculada sobre A_f e a visão bruta sobre S_f é preservada para transparência."))
    story.append(P("KPI 2 / proxy KQI - fração acima do limiar", "H2x"))
    story.append(P("<b>KPI2_f = 100 x #{i em S_f: delay_i > L} / #S_f</b>. Também se calcula KPI2_ativo sobre A_f. Unidade: %. Granularidade: fase. Fonte: DRB.RlcSduDelayDl."))
    story.append(P("Persistência operacional", "H2x"))
    story.append(P("Uma degradação é sustentada quando existe ao menos uma janela de W = 5 amostras consecutivas em que todas excedem L. O gatilho candidato exige simultaneamente KPI2_f > 50% e pelo menos uma janela sustentada. A dupla condição reduz falsos positivos por pico isolado e reproduz a lógica window_size=5/apply_votes=5 do decision.json."))
    story.append(table([
        ["Indicador", "População", "Unidade", "Decisão habilitada"],
        ["Mediana/p95 do delay", "A_f (primária) e S_f", "us", "Distinguir regime típico e cauda"],
        ["Fração delay > L", "S_f e A_f", "%", "Quantificar volume da degradação"],
        ["Janelas W=5", "S_f ordenada", "contagem", "Separar persistência de picos"],
    ], [4.0*cm,4.0*cm,2.3*cm,5.8*cm], ["LEFT","LEFT","CENTER","LEFT"]))
    story.append(PageBreak())

    add_title(story, "5. Resultados: comportamento temporal e distribuição")
    story += [line_chart(), P("Figura 1 - Série de atraso por fase. A fase stress permanece integralmente acima de L; recovery retorna ao regime de muitos zeros, mas apresenta picos de cauda.", "Caption")]
    rows=[["Fase","Mediana bruta","p95 bruto","n ativo","Mediana ativa","p95 ativo","Máximo"]]
    for p in PHASES:
        g=DF.loc[DF.phase==p]
        rows.append([PHASE_LABELS[p],fmt(ALL.loc[p,"mediana"],0),fmt(ALL.loc[p,"p95"],0),int(ACTIVE.loc[p,"n"]),fmt(ACTIVE.loc[p,"mediana"],0),fmt(ACTIVE.loc[p,"p95"],0),fmt(g.delay.max(),0)])
    story.append(table(rows,[2.4*cm,2.3*cm,2.1*cm,1.8*cm,2.5*cm,2.2*cm,1.9*cm]))
    story.append(P("Interpretação", "H2x"))
    story.append(P("Stress não se caracteriza por poucos outliers: suas 60 amostras têm atraso positivo e acima de L. A mediana ativa de 159 us é 16% maior que a baseline ativa (137 us), enquanto o p95 ativo de stress (191 us) é menor que o baseline ativo (204 us). Essa aparente inversão demonstra por que mediana e cauda devem ser lidas juntas: baseline é esparso, mas contém rajadas altas; stress é persistentemente degradado, embora mais concentrado."))
    story.append(P("Recovery apresenta mediana ativa de 126 us, sinal de melhora típica, porém p95 ativo de 438 us e máximo de 470 us, ambos superiores ao stress. Logo, a recuperação foi parcial na janela observada: o regime central normalizou, mas a cauda não." , "Callout"))
    story.append(PageBreak())

    add_title(story, "6. Resultado do KPI 2 e persistência")
    story += [bar_chart([float(KPI2[p]) for p in PHASES], "Fração de todas as amostras com atraso acima de L"), P("Figura 2 - KPI 2 sobre S_f. O cálculo inclui amostras ociosas como tempo sem degradação observada.", "Caption")]
    rows=[["Fase","KPI2 - todas","KPI2 - ativas","Janelas acima de L","Gatilho >50% + W5","Decisão"]]
    for p in PHASES:
        trig=KPI2[p]>50 and windows(p)>0
        rows.append([PHASE_LABELS[p],fmt(KPI2[p])+"%",fmt(KPI2_ACTIVE[p])+"%",f"{windows(p)}/{len(DF.loc[DF.phase==p])-4}","Sim" if trig else "Não","Aplicar (dry-run)" if trig else "Observar"])
    story.append(table(rows,[2.3*cm,2.5*cm,2.5*cm,2.8*cm,3.0*cm,3.0*cm]))
    story.append(P("Baseline e recovery excedem L em 25% do tempo total e em 55,6% das amostras ativas. Isso não deve ser rotulado como simples ruído: são rajadas reais do dataset. Entretanto, a alternância com zeros e valores baixos impede qualquer sequência de cinco excedências. Stress, por outro lado, mantém 100% de excedência e 56/56 janelas sustentadas."))
    story.append(P("A condição composta evita dois tipos de erro: disparar por uma única cauda severa de recovery ou ignorar um regime persistentemente elevado em stress porque seu p95 não é o maior do conjunto."))
    story.append(PageBreak())

    add_title(story, "7. Cruzamento entre atraso, vazão e carga")
    corr_all={p:DF.loc[DF.phase==p,["delay","thp"]].corr().iloc[0,1] for p in PHASES}
    corr_act={p:DF.loc[(DF.phase==p)&(DF.delay>0),["delay","thp"]].corr().iloc[0,1] for p in PHASES}
    mean_above=DF.groupby("above").thp.mean()
    rows=[["Fase","Correlação bruta delay x thp","Correlação ativa","Thp mediana (kbps)","PRB médio (%)"]]
    for p in PHASES: rows.append([PHASE_LABELS[p],fmt(corr_all[p],3),fmt(corr_act[p],3),fmt(ALL.loc[p,"thp_mediana"],1),fmt(ALL.loc[p,"prb_media"],1)])
    story.append(table(rows,[2.5*cm,3.8*cm,3.1*cm,3.4*cm,2.9*cm]))
    story.append(P(f"A vazão média nas amostras acima de L foi {fmt(mean_above[True],1)} kbps, contra {fmt(mean_above[False],1)} kbps fora da condição. Esse agregado não autoriza inferir que atraso alto sempre causa vazão baixa, porque as fases têm regimes e proporções de ociosidade diferentes. As correlações mudam ao excluir delay=0, evidenciando confusão por atividade de tráfego."))
    story.append(P("Leitura defensável", "H2x"))
    story.append(bullet("A evidência forte é temporal: stress mantém atraso acima de L em toda a fase."))
    story.append(bullet("A relação atraso-vazão é contextual, não causal; throughput UL e atraso RLC DL medem direções e fenômenos diferentes."))
    story.append(bullet("PRB UL fornece contexto de carga, mas não prova saturação DL nem causa raiz no RLC."))
    story.append(bullet("Para confirmar QoE real seriam necessários RTT ponta a ponta, jitter/perda, telemetria de aplicação e MOS/stalls."))
    story.append(P("Portanto, o cruzamento reforça a investigação operacional, mas não deve ser usado isoladamente para atribuir causalidade ou afirmar degradação de aplicação.", "Callout"))
    story.append(PageBreak())

    add_title(story, "8. Simulações e dados modificados para comparação")
    story.append(P("As simulações abaixo são contrafactuais: modificam cópias dos dados apenas para testar robustez. O dataset oficial permanece intacto. Cada cenário muda uma variável por vez e recalcula os indicadores."))
    # Scenarios
    stress=DF.loc[DF.phase=="stress","delay"].to_numpy().copy()
    recovery=DF.loc[DF.phase=="recovery","delay"].to_numpy().copy()
    s1=stress*0.75
    s2=stress.copy(); s2[::6]=80
    s3=recovery.copy(); s3[recovery>300]=140
    def scen(name, arr):
        return [name, fmt(np.median(arr),1), fmt(np.percentile(arr,95),1), fmt(100*np.mean(arr>L))+"%", f"{sum(bool((arr>L)[i:i+5].all()) for i in range(len(arr)-4))}/{len(arr)-4}"]
    rows=[["Cenário","Mediana (us)","p95 (us)","% > L","Janelas W5"]]
    rows += [scen("Stress original",stress),scen("S1: stress -25% de delay",s1),scen("S2: 1 alívio a cada 6 amostras",s2),scen("Recovery original",recovery),scen("S3: picos >300 us limitados a 140",s3)]
    story.append(table(rows,[6.0*cm,2.5*cm,2.2*cm,2.2*cm,2.7*cm],["LEFT","CENTER","CENTER","CENTER","CENTER"]))
    story.append(P("S1 - redução uniforme de 25%", "H2x")); story.append(P("Representa uma melhoria generalizada de processamento/agendamento. A mediana cai, mas o gatilho pode continuar ativo se a maior parte das amostras permanecer acima de 105,5 us. Isso mostra que uma melhoria relativa não é suficiente quando o nível absoluto ainda viola o critério."))
    story.append(P("S2 - alívio periódico", "H2x")); story.append(P("Substituir uma em cada seis amostras de stress por 80 us reduz a fração de excedência e as janelas de cinco consecutivas de 56 para 10. O cenário demonstra a função do critério de persistência: o alívio periódico reduz, mas não elimina, episódios sustentados; o gatilho ainda seria satisfeito e exigiria investigação."))
    story.append(P("S3 - remoção da cauda de recovery", "H2x")); story.append(P("Limitar apenas os dois picos acima de 300 us reduz fortemente o p95, sem alterar a massa de zeros nem transformar recovery em stress. Isso confirma que a principal anomalia da recovery está na cauda, e não no regime típico."))
    story.append(PageBreak())

    add_title(story, "9. Sensibilidade do limiar")
    thresholds=list(np.arange(50,251,10))
    story += [sensitivity_chart(thresholds), P("Figura 3 - Percentual de excedência em função do limiar. A separação é estável dentro da faixa vazia entre 95 e 133,7 us.", "Caption")]
    base=DF.loc[DF.phase=="baseline","delay"].to_numpy(); ba=base[base>0]
    criteria={"p50 baseline bruto":np.percentile(base,50),"p75 baseline bruto (oficial)":np.percentile(base,75),"p90 baseline bruto":np.percentile(base,90),"p75 baseline ativo":np.percentile(ba,75),"absoluto 150 us":150.0,"máximo baseline":base.max()}
    rows=[["Critério","L (us)","Baseline >L","Stress >L","Recovery >L"]]
    for name,t in criteria.items(): rows.append([name,fmt(t,1),fmt(100*np.mean(base>t))+"%",fmt(100*np.mean(DF.loc[DF.phase=="stress","delay"].to_numpy()>t))+"%",fmt(100*np.mean(DF.loc[DF.phase=="recovery","delay"].to_numpy()>t))+"%"])
    story.append(table(rows,[5.8*cm,2.2*cm,2.7*cm,2.7*cm,2.7*cm],["LEFT","CENTER","CENTER","CENTER","CENTER"]))
    story.append(P("A escolha do p75 ativo (171 us) entra no aglomerado de stress e reduz sensivelmente a detecção, podendo esconder degradação sustentada. Já L=150 us preserva a narrativa principal: stress permanece amplamente degradado e baseline/recovery têm incidência menor. O máximo do baseline (218 us) é conservador demais para detectar o regime típico de stress."))
    story.append(P("O ponto L=105,5 us não deve ser tratado como SLA universal. É um limiar estatístico didático, válido para este experimento e sustentado pela separação empírica. Em produção, L deve ser calibrado por serviço, 5QI/SLA, periodicidade, UE/célula e baseline representativo.", "Callout"))
    story.append(PageBreak())

    add_title(story, "10. Recomendação operacional e política A1 simulada")
    story.append(P("Decisão recomendada: <b>aplicar somente em dry-run na fase stress</b>. Baseline e recovery permanecem em observar/investigar, pois não atendem ao critério de persistência, embora recovery exija análise dos picos."))
    story.append(table([
        ["Elemento", "Definição"],
        ["Escopo", "Sessão/UE do experimento; sem generalização para a célula"],
        ["Gatilho", f"KPI2 > 50% E >= 1 janela de 5 amostras consecutivas com delay > {fmt(L)} us"],
        ["Ação candidata", "Priorizar tráfego ou investigar sessão/agendamento; decisão humana obrigatória"],
        ["Modo", "emulate / dry-run; nenhuma atuação real na RAN"],
        ["Encerramento", "Retornar a observar após janela estável; verificar cauda e recorrência"],
    ], [3.6*cm,12.5*cm],["LEFT","LEFT"]))
    story.append(P("Sequência operacional", "H2x"))
    for x in [
        "Confirmar integridade e frequência das amostras; correlacionar relógios.",
        "Validar atraso por UE/QFI/DRB e confrontar com PRB DL, BLER, retransmissões e buffer RLC.",
        "Medir RTT, jitter, perda e throughput ponta a ponta; coletar telemetria da aplicação.",
        "Executar política candidata em dry-run e comparar antes/depois com grupo de controle.",
        "Somente após validação e aprovação humana, planejar teste controlado com rollback.",
    ]: story.append(bullet(x))
    story.append(P("Critérios de validação", "H2x"))
    story.append(bullet("Redução do KPI2 e eliminação das janelas sustentadas sem piorar throughput, perda ou estabilidade."))
    story.append(bullet("Queda do p95 ativo sem deslocar a degradação para outro UE, QFI ou célula."))
    story.append(bullet("Confirmação por métrica ponta a ponta antes de declarar melhora de QoE."))
    story.append(P("Rollback", "H2x")); story.append(P("Como o laboratório é dry-run, o rollback consiste em descartar a decisão simulada. Em teste real futuro, registrar o estado anterior, limitar escopo/tempo da política e restaurar parâmetros originais se qualquer KPI de proteção piorar."))
    story.append(PageBreak())

    add_title(story, "11. Limitações, governança e ameaças à validade")
    for title, text in [
        ("Validade externa", "RFSIM, poucos UEs e janela curta impedem generalização para rede comercial, campus ou SLA real."),
        ("Constructo", "DRB.RlcSduDelayDl mede atraso RLC DL, não latência ponta a ponta nem QoE. DRB.UEThpUl é UL; o cruzamento é contextual."),
        ("Estatística", "A_f tem apenas 9 amostras em baseline/recovery. Percentis e correlações nessas fases têm alta incerteza."),
        ("Temporal", "Sem período de amostragem explícito, persistência é expressa em número de amostras, não duração."),
        ("Limiar", "L é estatístico e local ao dataset; não é cláusula de SLA nem alvo 5QI."),
        ("Causalidade", "Associação entre atraso, vazão e PRB não prova causa. São necessárias métricas DL, retransmissões e testes controlados."),
        ("Ética e privacidade", "Dados sintéticos de laboratório, sem dados pessoais. Em produção, IMSI/SUPI e identificadores devem ser minimizados/pseudonimizados."),
        ("Atuação", "A1 é uma intenção simulada. Nenhum handover, steering, prioridade ou configuração ocorreu de fato."),
    ]:
        story.append(KeepTogether([P(title,"H2x"),P(text)]))
    story.append(PageBreak())

    add_title(story, "12. Conclusões")
    story.append(P("Os dados respondem ao problema do G3 de forma objetiva: o atraso sugere experiência potencialmente ruim quando deixa de ser um pico e passa a dominar uma janela. Neste experimento, isso ocorre somente em stress, que apresenta 100% das amostras acima de 105,5 us e 56/56 janelas consecutivas de tamanho cinco."))
    story.append(P("A mediana e o p95 isolados seriam insuficientes. Baseline contém rajadas altas; recovery tem a maior cauda; stress, contudo, é a única fase com degradação persistente. A combinação de volume (KPI2) e persistência resolve essa ambiguidade e fornece um gatilho operacional defensável."))
    story.append(P("As simulações reforçam três conclusões: reduzir 25% do atraso pode não retirar a fase da condição crítica; inserir alívios periódicos reduz fortemente, mas não elimina, a persistência; e tratar os picos de recovery corrige principalmente a cauda. Portanto, ações distintas são exigidas para degradação sustentada e outliers."))
    story.append(P("Recomendação final", "H2x"))
    story.append(P("Manter a política A1 como candidata em dry-run, aplicada apenas quando KPI2 > 50% e houver janela W=5 acima de L. Antes de qualquer automação real, ampliar a amostra, definir a periodicidade, segmentar por UE/DRB/QFI, incorporar métricas DL e ponta a ponta e calibrar o limiar contra requisito de serviço. A conclusão deve permanecer formulada como <b>proxy de QoE</b>, nunca como QoE ou MOS efetivamente medidos.", "Callout"))
    story.append(P("Próximos passos", "H2x"))
    for x in ["Repetir o experimento com múltiplas sementes, UEs e níveis de carga.", "Adicionar PRB DL, BLER, retransmissão RLC/HARQ, buffer e RTT ponta a ponta.", "Registrar o intervalo de amostragem para transformar W=5 em duração operacional.", "Calibrar L por serviço/5QI e validar falsos positivos/falsos negativos.", "Construir painel com mediana, p95, KPI2, persistência e cauda de recovery."]: story.append(bullet(x))
    story.append(PageBreak())

    add_title(story, "Referências e rastreabilidade")
    refs = [
        "CESAR School. Aula 01 - Introdução e fontes de dados em telecom. Material do projeto, 2026.",
        "CESAR School. Aula 02 - Data lakes, big data e arquitetura bronze/silver/gold. 2026.",
        "CESAR School. Aula 03 - EDA, ETL e visualização. 2026.",
        "CESAR School. Aula 04 - KPIs, KQIs, medição e qualidade. 2026.",
        "CESAR School. Entregas - Projeto integrador (50%). 2026.",
        "Repositório da disciplina. data/docs/briefing-projeto.md e data/docs/temas-grupos.md.",
        "Dataset oficial do laboratório. data/code/datasets/kpm-ue-tp-sample/kpm.jsonl, kpm.sqlite, model.json e decision.json.",
        "Notebook do grupo. data/projeto-g3-latencia/notebook_g3_latencia.ipynb.",
    ]
    for i,r in enumerate(refs,1): story.append(P(f"{i}. {r}"))
    story.append(P("Nota de reprodutibilidade", "H2x"))
    story.append(P(f"Este relatório foi gerado automaticamente por data/projeto-g3-latencia/gerar_relatorio_g3.py, lendo diretamente {DATASET.relative_to(ROOT)}. O dataset original não foi modificado; os cenários contrafactuais foram mantidos apenas em memória."))
    story.append(P("Checklist de aderência", "H2x"))
    story.append(table([
        ["Requisito", "Evidência no relatório"],
        ["Dados e qualidade", "Seções 2 e 3"], ["ETL e arquitetura", "Seção 2"],
        ["2 KPIs/KQIs formais", "Seção 4"], ["Visualizações e análise", "Seções 5 a 9"],
        ["Recomendação/A1 dry-run", "Seção 10"], ["Limitações e ética", "Seção 11"],
        ["Conclusões defendidas", "Seção 12"],
    ], [6.0*cm,10.1*cm],["LEFT","LEFT"]))

    ReportDoc(str(OUTPUT)).build(story)
    print(OUTPUT)


if __name__ == "__main__":
    build()
