# -*- coding: utf-8 -*-
"""
Gera a apresentação do seminário do Projeto Integrador G3 — Latência / proxy de QoE.

Saída:
    apresentacao/figuras/*.png      — gráficos e diagramas (gerados a partir do dataset)
    apresentacao/seminario-g3-latencia.pdf

Reproduz: `python gerar_apresentacao.py` (na pasta apresentacao/).
Fonte única de dados: ../../code/datasets/kpm-ue-tp-sample/kpm.jsonl
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.font_manager as fm
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas as rl_canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

HERE = Path(__file__).resolve().parent
FIG = HERE / "figuras"
FIG.mkdir(parents=True, exist_ok=True)
DATA = HERE / "../../code/datasets/kpm-ue-tp-sample/kpm.jsonl"
DECISION = HERE / "../../code/datasets/kpm-ue-tp-sample/decision.json"
PDF_OUT = HERE / "seminario-g3-latencia.pdf"

# ----------------------------------------------------------------------------
# Paleta e tipografia
# ----------------------------------------------------------------------------
INK      = "#16202B"
MUTED    = "#5A6672"
HAIR     = "#D9DEE3"
PAPER    = "#FFFFFF"
CARD     = "#F5F7F8"
ACCENT   = "#0E7C86"   # "sinal" / telecom
AMBER    = "#B26A00"   # callout / zona morta
BASE_C   = "#4C6B8A"   # fase baseline
STRESS_C = "#C0392B"   # fase stress
REC_C    = "#2E7D5B"   # fase recovery
PHASE_C  = {"baseline": BASE_C, "stress": STRESS_C, "recovery": REC_C}

WIN = r"C:\Windows\Fonts"
FONTS = {
    "Segoe":    fr"{WIN}\segoeui.ttf",
    "Segoe-Bd": fr"{WIN}\segoeuib.ttf",
    "Segoe-Lt": fr"{WIN}\segoeuil.ttf",
    "Segoe-Sb": fr"{WIN}\segoeuisl.ttf",
    "Segoe-It": fr"{WIN}\segoeuii.ttf",
}
for name, path in FONTS.items():
    if Path(path).exists():
        pdfmetrics.registerFont(TTFont(name, path))
F_REG, F_BD, F_LT, F_SB, F_IT = "Segoe", "Segoe-Bd", "Segoe-Lt", "Segoe-Sb", "Segoe-It"

for path in (FONTS["Segoe"], FONTS["Segoe-Lt"], FONTS["Segoe-Bd"]):
    if Path(path).exists():
        fm.fontManager.addfont(path)
try:
    plt.rcParams["font.family"] = fm.FontProperties(fname=FONTS["Segoe"]).get_name()
except Exception:
    pass
plt.rcParams.update({
    "font.size": 12.5, "axes.edgecolor": MUTED, "axes.labelcolor": INK,
    "text.color": INK, "xtick.color": MUTED, "ytick.color": MUTED,
    "axes.titlecolor": INK, "figure.facecolor": "white", "axes.facecolor": "white",
    "svg.fonttype": "none",
})

# ----------------------------------------------------------------------------
# Dados + cálculos (idênticos ao notebook)
# ----------------------------------------------------------------------------
recs = [json.loads(l) for l in DATA.read_text(encoding="utf-8").splitlines() if l.strip()]
raw = pd.json_normalize(recs)
df = raw.rename(columns={
    "metrics.DRB.RlcSduDelayDl": "delay", "metrics.DRB.UEThpUl": "thp",
    "metrics.RRU.PrbTotUl": "prb",
})[["phase", "sample_index", "delay", "thp", "prb"]]
df["phase"] = pd.Categorical(df["phase"], ["baseline", "stress", "recovery"], ordered=True)
df = df.sort_values(["phase", "sample_index"]).reset_index(drop=True)
df["gidx"] = range(len(df))  # índice global para série contínua

PH = ["baseline", "stress", "recovery"]
arr = {p: df.loc[df.phase == p, "delay"].to_numpy() for p in PH}
arr_a = {p: v[v > 0] for p, v in arr.items()}
N = {p: len(arr[p]) for p in PH}

L = float(np.percentile(arr["baseline"], 75))          # 105.5
GAP_LO = float(arr_a["baseline"][arr_a["baseline"] <= 100].max())   # 95
GAP_HI = float(arr["stress"].min())                    # 133.7

def pctl(a, q): return float(np.percentile(a, q))
def frac_above(a, thr): return round(100 * float(np.mean(a > thr)), 1)

kpi1_bruto = {p: (round(float(np.median(arr[p])), 1), round(pctl(arr[p], 95), 1)) for p in PH}
kpi1_ativo = {p: (round(float(np.median(arr_a[p])), 1), round(pctl(arr_a[p], 95), 1)) for p in PH}
kpi2_S = {p: frac_above(arr[p], L) for p in PH}
kpi2_A = {p: frac_above(arr_a[p], L) for p in PH}

W = 5
def janelas(a, thr=L, w=W):
    v = a > thr
    return sum(bool(v[i - w + 1:i + 1].all()) for i in range(w - 1, len(v))), max(0, len(v) - w + 1)
jan = {p: janelas(arr[p]) for p in PH}

idle = {p: int((arr[p] == 0).sum()) for p in PH}

rng = np.random.default_rng(42)
def boot_p75(a, n=5000):
    idx = rng.integers(0, len(a), size=(n, len(a)))
    return np.percentile(a[idx], 75, axis=1)
bs_bruto = boot_p75(arr["baseline"])
bs_ativo = boot_p75(arr_a["baseline"])
cv_bruto = bs_bruto.std() / bs_bruto.mean()
cv_ativo = bs_ativo.std() / bs_ativo.mean()

corr_a = {p: float(pd.Series(arr_a[p]).corr(
    pd.Series(df.loc[(df.phase == p) & (df.delay > 0), "thp"].to_numpy()))) for p in PH}
thp_above = float(df.loc[df.delay > L, "thp"].mean())
thp_below = float(df.loc[df.delay <= L, "thp"].mean())

dec = json.loads(DECISION.read_text(encoding="utf-8"))

NUM = dict(L=L, GAP_LO=GAP_LO, GAP_HI=GAP_HI, kpi1_bruto=kpi1_bruto, kpi1_ativo=kpi1_ativo,
           kpi2_S=kpi2_S, kpi2_A=kpi2_A, jan=jan, idle=idle, N=N,
           cv_bruto=cv_bruto, cv_ativo=cv_ativo, corr_a=corr_a,
           thp_above=thp_above, thp_below=thp_below)
print(json.dumps({k: (v if not isinstance(v, dict) else {kk: str(vv) for kk, vv in v.items()})
                  for k, v in NUM.items()}, indent=2, ensure_ascii=False, default=str))

# ----------------------------------------------------------------------------
# Helpers de chart
# ----------------------------------------------------------------------------
def _finish(ax):
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.grid(axis="y", color=HAIR, lw=0.8)
    ax.set_axisbelow(True)

def save(fig, name):
    fig.savefig(FIG / name, dpi=200, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print("  fig:", name)

# 1. cover hero — série de atraso das 100 amostras
def fig_hero():
    fig, ax = plt.subplots(figsize=(15.0, 1.75))
    ax.fill_between(df.gidx, df.delay, color=ACCENT, alpha=0.12, lw=0)
    ax.plot(df.gidx, df.delay, color=ACCENT, lw=1.6)
    for p in PH:
        g = df[df.phase == p]
        ax.axvspan(g.gidx.min(), g.gidx.max() + 1, color=PHASE_C[p], alpha=0.06, lw=0)
    ax.set_xlim(0, len(df)); ax.set_ylim(0, df.delay.max() * 1.08)
    ax.set_xticks([]); ax.set_yticks([])
    for s in ax.spines.values():
        s.set_visible(False)
    save(fig, "hero.png")

# 2. timeline das fases
def fig_timeline():
    fig, ax = plt.subplots(figsize=(11.4, 1.9))
    x = 0
    for p in PH:
        ax.barh(0, N[p], left=x, height=0.6, color=PHASE_C[p], edgecolor="white")
        ax.text(x + N[p] / 2, 0, f"{p}\n{N[p]} amostras", ha="center", va="center",
                color="white", fontsize=12.5, fontweight="bold")
        x += N[p]
    ax.set_xlim(0, 100); ax.set_ylim(-0.5, 0.5)
    ax.set_yticks([]); ax.set_xlabel("amostra KPM (1 ponto = 1 medição)  ·  experimento ue-tp-20260804-174422")
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    save(fig, "timeline.png")

# 3. amostras ociosas
def fig_ociosas():
    fig, ax = plt.subplots(figsize=(7.6, 4.3))
    ativ = [N[p] - idle[p] for p in PH]
    oci = [idle[p] for p in PH]
    ax.bar(PH, ativ, color=[PHASE_C[p] for p in PH], label="com tráfego DL (delay > 0)")
    ax.bar(PH, oci, bottom=ativ, color=HAIR, label="ociosa (delay = 0)")
    for i, p in enumerate(PH):
        if idle[p]:
            ax.text(i, N[p] - idle[p] / 2, f"{idle[p]}/{N[p]}\n({100*idle[p]/N[p]:.0f}%)",
                    ha="center", va="center", fontsize=11, color=MUTED)
    ax.set_ylabel("nº de amostras"); _finish(ax)
    ax.legend(frameon=False, fontsize=11)
    save(fig, "ociosas.png")

# 4. série do atraso por fase + limiar
def fig_serie():
    fig, ax = plt.subplots(figsize=(11.2, 4.6))
    for p in PH:
        g = df[df.phase == p]
        ax.plot(g.gidx, g.delay, marker="o", ms=3.5, lw=1.3, color=PHASE_C[p], label=p)
    ax.axhline(L, color=AMBER, ls="--", lw=1.4)
    ax.text(42, L + 12, f"limiar L = {L:.1f} µs", ha="left", color=AMBER, fontsize=11)
    ax.set_xlabel("amostra (ordem: baseline - stress - recovery)")
    ax.set_ylabel("DRB.RlcSduDelayDl  (µs)")
    _finish(ax); ax.legend(frameon=False, ncol=3, fontsize=11)
    save(fig, "serie.png")

# 5. boxplot
def fig_box():
    fig, ax = plt.subplots(figsize=(7.8, 4.6))
    data = [arr[p] for p in PH]
    bp = ax.boxplot(data, tick_labels=PH, showmeans=True, widths=0.55, patch_artist=True,
                    medianprops=dict(color=INK, lw=1.6),
                    meanprops=dict(marker="D", mfc="white", mec=INK, ms=6))
    for patch, p in zip(bp["boxes"], PH):
        patch.set_facecolor(PHASE_C[p]); patch.set_alpha(0.28); patch.set_edgecolor(PHASE_C[p])
    for w in bp["whiskers"] + bp["caps"]:
        w.set_color(MUTED)
    ax.axhline(L, color=AMBER, ls="--", lw=1.3)
    ax.set_ylabel("DRB.RlcSduDelayDl  (µs)"); _finish(ax)
    save(fig, "boxplot.png")

# 6. zona morta (strip)
def fig_deadzone():
    fig, ax = plt.subplots(figsize=(11.4, 3.6))
    ax.axvspan(GAP_LO, GAP_HI, color=AMBER, alpha=0.16, lw=0)
    jit = dict(baseline=0.30, stress=0.0, recovery=-0.30)
    ax.scatter(np.zeros(idle["baseline"]), np.full(idle["baseline"], jit["baseline"]),
               s=34, facecolors="none", edgecolors=BASE_C, lw=1.1)
    for p in PH:
        a = arr_a[p]
        ax.scatter(a, np.full(len(a), jit[p]), s=48, color=PHASE_C[p], alpha=0.85,
                   label=f"{p} (tráfego ativo)")
    ax.axvline(L, color=INK, ls=":", lw=1.6)
    ax.text(L, 0.70, f"L = {L:.1f} µs".replace(".", ","), ha="center", va="bottom",
            color=INK, fontsize=10)
    gap_hi_pt = f"{GAP_HI:.1f}".replace(".", ",")
    ax.text((GAP_LO + GAP_HI) / 2, -0.74, f"zona morta {GAP_LO:.0f} ≤ L < {gap_hi_pt} µs · nenhuma amostra",
            ha="center", va="top", color=AMBER, fontsize=10.5)
    ax.set_ylim(-0.98, 0.92); ax.set_xlim(-15, 485); ax.set_yticks([])
    ax.set_xlabel("DRB.RlcSduDelayDl  (µs)   ·   ○ = amostras ociosas do baseline (delay = 0)")
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.legend(frameon=False, fontsize=9.5, loc="lower center",
              bbox_to_anchor=(0.5, -0.42), ncol=3)
    save(fig, "deadzone.png")

# 7. sweep de sensibilidade
def fig_sweep():
    Ls = np.arange(60, 261, 1.0)
    fig, ax = plt.subplots(figsize=(11.2, 4.5))
    for p in PH:
        y = [frac_above(arr[p], t) for t in Ls]
        ax.plot(Ls, y, lw=2.2, color=PHASE_C[p], label=f"KPI 2 — {p}")
    ax.axvspan(GAP_LO, GAP_HI, color=AMBER, alpha=0.15, lw=0)
    ax.axvline(L, color=INK, ls=":", lw=1.5)
    ax.text(L + 2, 92, f"L = {L:.1f} µs", color=INK, fontsize=10.5)
    for xv, lab in [(150, "150 µs\n(abs.)"), (171, "171 µs\n(p75 só-ativo)")]:
        ax.axvline(xv, color=MUTED, ls="--", lw=0.9)
        ax.text(xv + 2, 62, lab, color=MUTED, fontsize=9)
    ax.set_xlabel("limiar L  (µs)"); ax.set_ylabel("% de amostras da fase acima de L")
    ax.set_ylim(-3, 105); _finish(ax); ax.legend(frameon=False, fontsize=11)
    save(fig, "sweep.png")

# 8. bootstrap do p75
def fig_bootstrap():
    fig, ax = plt.subplots(figsize=(9.8, 4.3))
    bins = np.arange(0, 232, 8)
    ax.hist(bs_bruto, bins=bins, color=BASE_C, alpha=0.55,
            label=f"p75 baseline BRUTO (n=20) — CV {cv_bruto:.0%}, IC95% ~ [10; 174]")
    ax.hist(bs_ativo, bins=bins, color=ACCENT, alpha=0.55,
            label=f"p75 baseline SÓ-ATIVO (n=9) — CV {cv_ativo:.0%}, IC95% ~ [95; 218]")
    ax.axvline(np.percentile(arr["baseline"], 75), color=BASE_C, lw=2, ls="--")
    ax.axvline(np.percentile(arr_a["baseline"], 75), color=ACCENT, lw=2, ls="--")
    ax.set_xlabel("valor do p75 em 5 000 reamostragens do baseline  (µs)")
    ax.set_ylabel("frequência"); _finish(ax); ax.set_ylim(0, 1750)
    ax.legend(frameon=False, fontsize=9.5, loc="upper left")
    save(fig, "bootstrap.png")

# 9. KPI 2 barras (S vs A) + janelas
def fig_kpi2():
    fig, ax = plt.subplots(figsize=(9.8, 4.5))
    x = np.arange(3); w = 0.36
    s = [NUM["kpi2_S"][p] for p in PH]
    a = [NUM["kpi2_A"][p] for p in PH]
    b1 = ax.bar(x - w/2, s, w, color=[PHASE_C[p] for p in PH], label="KPI 2 sobre todas as amostras (Sf)")
    b2 = ax.bar(x + w/2, a, w, color=[PHASE_C[p] for p in PH], alpha=0.45,
                label="KPI 2 sobre tráfego ativo (Af)")
    for bars in (b1, b2):
        ax.bar_label(bars, fmt="%.1f%%", fontsize=10, color=INK, padding=2)
    for i, p in enumerate(PH):
        f, tot = NUM["jan"][p]
        ax.text(i, -14, f"janelas de 5\n{f}/{tot}", ha="center", fontsize=9.5, color=MUTED)
    ax.set_xticks(x); ax.set_xticklabels(PH)
    ax.set_ylabel("% de amostras acima de L"); ax.set_ylim(-22, 122)
    _finish(ax); ax.legend(frameon=False, fontsize=10, loc="lower center",
                           bbox_to_anchor=(0.5, 1.0), ncol=2)
    save(fig, "kpi2.png")

# 10. scatter atraso x vazão
def fig_scatter():
    fig, ax = plt.subplots(figsize=(9.8, 4.6))
    for p in PH:
        g = df[df.phase == p]
        ax.scatter(g.thp.clip(lower=1), g.delay, s=26, alpha=0.75, color=PHASE_C[p], label=p)
    ax.axhline(L, color=AMBER, ls="--", lw=1.2)
    ax.set_xscale("log")
    ax.set_xlabel("DRB.UEThpUl  (kbps, escala log)")
    ax.set_ylabel("DRB.RlcSduDelayDl  (µs)")
    _finish(ax); ax.grid(axis="x", color=HAIR, lw=0.6)
    ax.legend(frameon=False, fontsize=11)
    save(fig, "scatter.png")

# 11. pipeline bronze/silver/gold
def _box(ax, x, y, w, h, title, sub, fc, tc="white"):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.03",
                                fc=fc, ec="none"))
    ax.text(x + w/2, y + h*0.62, title, ha="center", va="center", color=tc,
            fontsize=13, fontweight="bold")
    ax.text(x + w/2, y + h*0.26, sub, ha="center", va="center", color=tc, fontsize=10)

def _arrow(ax, x0, x1, y):
    ax.add_patch(FancyArrowPatch((x0, y), (x1, y), arrowstyle="-|>", mutation_scale=18,
                                 color=MUTED, lw=1.6))

def fig_pipeline():
    fig, ax = plt.subplots(figsize=(11.6, 3.1))
    ax.set_xlim(0, 12); ax.set_ylim(0, 3); ax.axis("off")
    _box(ax, 0.2, 0.9, 3.2, 1.4, "BRONZE", "kpm.jsonl · bruto\n1 registro por linha", BASE_C)
    _box(ax, 4.4, 0.9, 3.2, 1.4, "SILVER", "kpm.sqlite · tipado\nruns + kpm_samples", ACCENT)
    _box(ax, 8.6, 0.9, 3.2, 1.4, "GOLD", "KPIs + decision.json\npronto p/ decisão", REC_C)
    _arrow(ax, 3.5, 4.3, 1.6); _arrow(ax, 7.7, 8.5, 1.6)
    ax.text(6, 0.35, "InfluxDB / Redis RNIB: não usados — trilha offline, sem RIC near-RT ao vivo",
            ha="center", fontsize=9.5, color=MUTED, style="italic")
    save(fig, "pipeline.png")

# 12. fluxo da decisão A1
def _arrow2(ax, p0, p1):
    ax.add_patch(FancyArrowPatch(p0, p1, arrowstyle="-|>", mutation_scale=16,
                                 color=MUTED, lw=1.5))

def fig_fluxo():
    fig, ax = plt.subplots(figsize=(11.8, 4.2))
    ax.set_xlim(0, 12.4); ax.set_ylim(0, 5); ax.axis("off")
    _box(ax, 0.15, 1.95, 2.2, 1.3, "Fase f", "KPI 2 + série\nde atraso", MUTED)
    _box(ax, 3.05, 3.25, 3.15, 1.2, "condição 1 · volume", "KPI2(f) > 50 %", INK)
    _box(ax, 3.05, 0.55, 3.15, 1.2, "condição 2 · persistência",
         f">= 1 janela de {W}\namostras > L", INK)
    _box(ax, 6.95, 1.95, 2.15, 1.3, "E", "as duas\nverdadeiras?", AMBER)
    _box(ax, 9.85, 3.05, 2.35, 1.15, "apply", "priorizar tráfego\n(dry-run)", STRESS_C)
    _box(ax, 9.85, 1.0, 2.35, 1.15, "observe", "sem ação", REC_C)
    _arrow2(ax, (2.35, 2.6), (3.0, 3.85))
    _arrow2(ax, (2.35, 2.6), (3.0, 1.15))
    _arrow2(ax, (6.2, 3.85), (6.9, 2.95))
    _arrow2(ax, (6.2, 1.15), (6.9, 2.25))
    _arrow2(ax, (9.15, 2.78), (9.8, 3.5))
    _arrow2(ax, (9.15, 2.42), (9.8, 1.7))
    ax.text(9.62, 3.62, "stress", ha="right", fontsize=9.5, color=STRESS_C)
    ax.text(9.62, 1.52, "baseline / recovery", ha="right", fontsize=9.5, color=REC_C)
    ax.text(6.2, 0.06, "Espelha decision.json do lab:  window_size = 5  ·  apply_votes = 5  ·  "
            "actuation = emulate  (nada é aplicado num RIC real)",
            ha="center", fontsize=9.3, color=MUTED, style="italic")
    save(fig, "fluxo.png")

for fn in (fig_hero, fig_timeline, fig_ociosas, fig_serie, fig_box, fig_deadzone,
           fig_sweep, fig_bootstrap, fig_kpi2, fig_scatter, fig_pipeline, fig_fluxo):
    fn()

# ----------------------------------------------------------------------------
# PDF
# ----------------------------------------------------------------------------
PW, PH_ = 960, 540
MX = 64
c = rl_canvas.Canvas(str(PDF_OUT), pagesize=(PW, PH_))
c.setTitle("Seminário G3 — Latência / proxy de QoE")
c.setAuthor("Grupo G3 · Módulo 09 — CESAR School")

_page = {"n": 0}
CT = PH_ - 138          # topo da área de conteúdo (abaixo do título)

def rgb(hexs):
    h = hexs.lstrip("#")
    return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))

def set_fill(hexs): c.setFillColorRGB(*rgb(hexs))
def set_stroke(hexs): c.setStrokeColorRGB(*rgb(hexs))

def _g(s):  # Segoe UI não tem U+2208
    return s.replace("∈", " de ")

def text(x, y, s, font=F_REG, size=15, color=INK, align="l"):
    s = _g(s); set_fill(color); c.setFont(font, size)
    if align == "l": c.drawString(x, y, s)
    elif align == "c": c.drawCentredString(x, y, s)
    else: c.drawRightString(x, y, s)

def para(x, y, s, font=F_REG, size=15, color=INK, leading=None, width_chars=92):
    import textwrap
    s = _g(s)
    leading = leading or size * 1.5
    set_fill(color); c.setFont(font, size)
    lines = textwrap.wrap(s, width_chars)
    for i, line in enumerate(lines):
        c.drawString(x, y - i * leading, line)
    return y - len(lines) * leading

def footer():
    set_stroke(HAIR); c.setLineWidth(0.8)
    c.line(MX, 42, PW - MX, 42)
    text(MX, 26, "G3 · Latência / proxy de QoE", F_REG, 9.5, MUTED)
    text(PW / 2, 26, "Seminário — Projeto Integrador · Módulo 09 · CESAR School", F_REG, 9.5, MUTED, "c")
    text(PW - MX, 26, f"{_page['n']:02d}", F_REG, 9.5, MUTED, "r")

def new_page(kicker=None, title=None, title_size=30):
    if _page["n"] > 0:
        footer(); c.showPage()
    _page["n"] += 1
    set_fill(PAPER); c.rect(0, 0, PW, PH_, fill=1, stroke=0)
    if title is not None:
        set_fill(ACCENT); c.rect(MX, PH_ - 96, 3, 46, fill=1, stroke=0)
        if kicker:
            text(MX + 16, PH_ - 60, kicker.upper(), F_SB, 11.5, ACCENT)
        text(MX + 16, PH_ - 90, title, F_LT, title_size, INK)

def image(path, x, y, w, h=None, caption=None):
    ir = ImageReader(str(path))
    iw, ih = ir.getSize()
    if h is None:
        h = w * ih / iw
    else:
        scale = min(w / iw, h / ih)
        w, h = iw * scale, ih * scale
    c.drawImage(ir, x, y, width=w, height=h, mask="auto")
    if caption:
        text(x, y - 14, caption, F_IT, 9.5, MUTED)
    return w, h

def img(path, x, top, max_w, max_h, align="l", caption=None):
    """Coloca a imagem ancorada pelo TOPO (top = coord y da borda superior)."""
    ir = ImageReader(str(path))
    iw, ih = ir.getSize()
    scale = min(max_w / iw, max_h / ih)
    w, h = iw * scale, ih * scale
    if align == "c":
        x = x + (max_w - w) / 2
    elif align == "r":
        x = x + (max_w - w)
    c.drawImage(ir, x, top - h, width=w, height=h, mask="auto")
    if caption:
        text(x, top - h - 13, caption, F_IT, 9.5, MUTED)
    return w, h, top - h

def bullets(x, y, items, size=14.5, gap=30, color=INK, lead=18, width_chars=78):
    import textwrap
    for it in items:
        it = _g(it)
        set_fill(ACCENT); c.setFont(F_BD, size); c.drawString(x, y, "•")
        set_fill(color); c.setFont(F_REG, size)
        lines = textwrap.wrap(it, width_chars)
        for j, ln in enumerate(lines):
            c.drawString(x + 18, y - j * lead, ln)
        y -= max(gap, len(lines) * lead + 10)
    return y

def card(x, y, w, h):
    set_fill(CARD); c.roundRect(x, y, w, h, 10, fill=1, stroke=0)

def stat(x, y, value, label, vcolor=INK):
    text(x, y, value, F_LT, 30, vcolor)
    text(x, y - 20, label, F_REG, 10.5, MUTED)

# ---- 01 capa ----
_page["n"] = 1
set_fill(PAPER); c.rect(0, 0, PW, PH_, fill=1, stroke=0)
img(FIG / "hero.png", 0, 172, PW, 105)                       # faixa de dados no rodapé
set_stroke(HAIR); c.setLineWidth(0.8); c.line(0, 172, PW, 172)
set_fill(ACCENT); c.rect(MX, PH_ - 150, 60, 5, fill=1, stroke=0)
text(MX, PH_ - 192, "PROJETO INTEGRADOR · G3", F_SB, 14, ACCENT)
text(MX, PH_ - 240, "Latência de rádio como proxy de QoE", F_LT, 40, INK)
text(MX, PH_ - 274, "Quando o atraso no enlace sugere experiência ruim — e o que fazer com isso", F_REG, 15, MUTED)
text(MX, 232, "Análise de Dados em Redes de Telecom — Módulo 09 · CESAR School", F_REG, 12.5, INK)
text(MX, 211, "Equipe: Carlos Alberto · Éverton Gomes · Gerson Francisco · Luiz Carlos Santos", F_REG, 12, MUTED)
text(MX, 190, "Seminário — Aula 06 · 29/08/2026    ·    dados: lab OAI RFSIM · ue-tp-20260804-174422 · 100 amostras",
     F_IT, 10.5, MUTED)

# ---- 02 pergunta ----  (new_page finaliza a capa: footer + showPage)
new_page("O problema", "A pergunta do grupo")
y = para(MX + 16, PH_ - 150,
         "Quando o atraso de rádio (DRB.RlcSduDelayDl) sugere que a experiência do usuário pode "
         "estar ruim? Usamos o atraso como proxy de QoE.", F_LT, 20, INK, leading=30, width_chars=78)
y = bullets(MX + 16, y - 24, [
    "O laboratório não produz nota MOS de aplicativo real — toda conclusão é sobre o proxy técnico, não sobre QoE medida junto ao usuário.",
    "Sinal reforçado quando atraso alto coincide com vazão baixa (DRB.UEThpUl).",
    "Entregáveis exigidos pelo briefing: 2 indicadores com fórmula, visualizações, recomendação / política A1 simulada e limitações.",
])
card(MX + 16, 70, PW - 2 * MX - 32, 90)
stat(MX + 44, 132, "100", "amostras KPM")
stat(MX + 200, 132, "3", "fases do experimento")
stat(MX + 380, 132, "3", "métricas: atraso · vazão UL · PRB UL")
stat(MX + 660, 132, "proxy", "atraso ≠ MOS")

# ---- 03 dados ----
new_page("Os dados", "Origem e forma dos dados")
img(FIG / "timeline.png", MX + 8, CT, PW - 2 * MX - 16, 130, align="c")
bullets(MX + 16, CT - 150, [
    "Artefatos KPM oficiais do docente (trilha offline obrigatória), gerados no lab oai-cn-gnb-nonrt-nearrt — RFSIM, telemetria sintética, sem dados pessoais.",
    "baseline = comportamento normal · stress = janela de carga · recovery = pós-carga.",
    "Métricas: DRB.RlcSduDelayDl (µs) · DRB.UEThpUl (kbps) · RRU.PrbTotUl (%).",
], gap=30, size=13.5)

# ---- 04 arquitetura ----
new_page("Arquitetura", "Onde os dados ficam — bronze / silver / gold")
img(FIG / "pipeline.png", MX + 8, CT, 720, 190, align="c")
bullets(MX + 16, CT - 205, [
    "Bronze — kpm.jsonl: espelho bruto, schema-on-read.",
    "Silver — kpm.sqlite: tipado, consultável por SQL (runs + kpm_samples).",
    "Gold — indicadores deste projeto + decision.json (recomendação em dry-run).",
    "Sem InfluxDB / Redis RNIB: trilha offline, sem RIC near-RT ao vivo nem inventário E2.",
], gap=26, size=13.5, width_chars=104)

# ---- 05 qualidade ----
new_page("Qualidade", "Checagem antes de qualquer indicador")
img(FIG / "ociosas.png", PW - MX - 400, CT + 6, 392, 250, align="r")
yy = bullets(MX + 16, CT, [
    "100 amostras, 0 valores nulos, 0 duplicados (run_id + phase + sample_index).",
    "Achado central: 55 % das amostras de baseline e de recovery são ociosas — delay = 0.",
    "Sem tráfego DL não há SDU RLC para medir; delay = 0 significa \"nada a medir\", não \"ótimo\".",
    "Em stress, 100 % das amostras apresentam atividade DL mensurável no experimento.",
], width_chars=50, gap=42, size=13.5)
para(MX + 16, yy + 2,
     "Consequência: cada indicador é calculado de duas formas — bruto (todas as amostras, Sf) "
     "e só tráfego ativo (delay > 0, Af).", F_IT, 12.5, MUTED, width_chars=50)

# ---- 06 KPI 1 série ----
new_page("Indicador 1", "KPI 1 — Atraso RLC por fase (mediana e p95)")
b = kpi1_ativo
text(MX + 16, CT,
     f"Sobre tráfego ativo (Af):  baseline {b['baseline'][0]:.0f} / {b['baseline'][1]:.0f} µs    ·    "
     f"stress {b['stress'][0]:.0f} / {b['stress'][1]:.0f} µs    ·    "
     f"recovery {b['recovery'][0]:.0f} / {b['recovery'][1]:.0f} µs     (mediana / p95)",
     F_REG, 13.5, INK)
text(MX + 16, CT - 20,
     "A mediana mostra o comportamento típico; o p95 caracteriza a cauda elevada, superada por apenas 5 % das observações.",
     F_IT, 11.5, MUTED)
img(FIG / "serie.png", MX + 8, CT - 40, PW - 2 * MX - 16, 320, align="c")

# ---- 07 KPI 1 boxplot ----
new_page("Indicador 1", "KPI 1 — Distribuição do atraso por fase")
img(FIG / "boxplot.png", MX + 8, CT, 400, 290)
bullets(PW - MX - 400, CT, [
    "stress: distribuição compacta e deslocada para cima (mediana ~159 µs, dispersão baixa) — degradação consistente.",
    "baseline / recovery: caixa \"esmagada\" no zero pelas amostras ociosas, com cauda que alcança o patamar de stress.",
    "recovery tem outliers de 390 e 470 µs — acima do pior caso de stress (265 µs).",
], width_chars=46, gap=46, size=13.5)

# ---- 08 KPI 2 definição ----
new_page("Indicador 2", "KPI 2 — Fração de tempo em degradação")
card(MX + 16, CT - 96, PW - 2 * MX - 32, 96)
text(MX + 40, CT - 26, "KPI2(f)  =  100 · (amostras de Sf com delay_i > L) / (total de amostras de Sf)   [%]", F_SB, 15, INK)
text(MX + 40, CT - 54, f"L = {L:.1f} µs      versão paralela KPI2_ativo sobre Af (sem viés de amostras ociosas)", F_REG, 12.5, MUTED)
text(MX + 40, CT - 78, "gatilho de degradação sustentada: ≥ 1 janela de 5 amostras consecutivas com delay > L", F_REG, 12.5, MUTED)
bullets(MX + 16, CT - 128, [
    "O limiar precisa separar o regime \"sem carga\" do regime \"com carga\" — e ser defensável, não arbitrário.",
    "Escolha inicial: p75 do atraso na fase baseline. Valor = 105,5 µs. As duas telas seguintes validam essa escolha.",
], gap=32)

# ---- 09 zona morta ----
new_page("Validação do limiar", "Por que 95 ≤ L < 133,7 µs dá o mesmo resultado")
img(FIG / "deadzone.png", MX + 8, CT, PW - 2 * MX - 16, 300, align="c")
para(MX + 16, CT - 300,
     f"O baseline é bimodal: 11 amostras ociosas em 0 µs e 9 ativas entre 39 e 218 µs. A fase stress "
     f"começa em {str(f'{GAP_HI:.1f}').replace('.', ',')} µs. Para {GAP_LO:.0f} ≤ L < {str(f'{GAP_HI:.1f}').replace('.', ',')} µs, nenhuma observação muda de lado — "
     f"mover L dentro desse intervalo não altera o KPI 2. O número do percentil é frágil; a decisão que ele gera, não.",
     F_REG, 12.5, INK, leading=19, width_chars=120)

# ---- 10 sweep ----
new_page("Validação do limiar", "Sensibilidade — o critério muda a conclusão?")
text(MX + 16, CT,
     "Plateau em [95; 133] µs: KPI 2 = baseline 25 % · stress 100 % · recovery 25 % para todo L nessa faixa.",
     F_REG, 13, INK)
text(MX + 16, CT - 20,
     "Rejeitados: p75 só-ativo (171 µs) e cauda alta do baseline caem dentro de stress e derrubam o "
     "KPI 2 de stress para ~22 %. mediana + k·MAD degenera (MAD = 0).",
     F_IT, 11, MUTED)
img(FIG / "sweep.png", MX + 8, CT - 40, PW - 2 * MX - 16, 320, align="c")

# ---- 11 bootstrap ----
new_page("Validação do limiar", "O ponto de percentil é instável — a decisão não é")
img(FIG / "bootstrap.png", MX + 8, CT, 452, 285)
bullets(PW - MX - 348, CT, [
    f"p75 baseline bruto: CV {cv_bruto:.0%}, IC95 % ≈ [10; 174] µs — muito sensível à fração de amostras ociosas.",
    f"p75 baseline só-ativo: CV {cv_ativo:.0%}, bem mais estável, mas só 9 amostras e cai dentro de stress.",
    "Decisão: manter L = 105,5 µs, lido como \"ponto da zona morta\". Âncora de sanidade: 150 µs conta a mesma história.",
], width_chars=42, gap=48, size=12.5)

# ---- 12 fórmula final + resultados ----
new_page("Resultado", "KPI 2 — resultados e fórmula final")
img(FIG / "kpi2.png", MX + 8, CT, 430, 285)
x0 = PW - MX - 372
text(x0, CT, "Fórmula final", F_SB, 13, ACCENT)
para(x0, CT - 22, "KPI 1: mediana e p95 de DRB.RlcSduDelayDl sobre Af, por fase (bruto sobre Sf em paralelo).",
     F_REG, 12, INK, leading=17, width_chars=46)
para(x0, CT - 90, "KPI 2: % de Sf com delay > L (L = 105,5 µs); KPI2_ativo sobre Af; gatilho = janela de 5 consecutivas.",
     F_REG, 12, INK, leading=17, width_chars=46)
text(x0, CT - 180, "Leitura", F_SB, 13, ACCENT)
para(x0, CT - 202, "stress: 100 % e 56/56 janelas — degradação sustentada. baseline / recovery: 25 %, 0 janelas — "
     "rajadas isoladas. KPI2_ativo 55,6 % expõe que, com tráfego, o baseline já opera em patamar alto.",
     F_REG, 11.5, MUTED, leading=16, width_chars=46)

# ---- 13 vazão ----
new_page("Cruzamento", "Atraso e vazão — contexto operacional do proxy")
img(FIG / "scatter.png", MX + 8, CT, 448, 285)
bullets(PW - MX - 356, CT, [
    f"Vazão média fora do limiar: {thp_below / 1000:.2f} Mb/s  ·  acima: {thp_above / 1000:.2f} Mb/s — atraso alto acompanha as janelas de maior atividade.",
    f"Correlação delay-thp (tráfego ativo): baseline {corr_a['baseline']:+.2f} · stress {corr_a['stress']:+.2f} · recovery {corr_a['recovery']:+.2f}.",
    "A associação não demonstra causalidade nem confirma QoE ruim: vazão UL e atraso RLC DL medem direções e fenômenos diferentes.",
], width_chars=44, gap=46, size=12.5)

# ---- 14 recomendação / A1 ----
new_page("Recomendação", "Política A1 candidata — execução simulada (dry-run)")
text(MX + 16, CT,
     "Durante stress: priorização de tráfego / investigação de sessão. Gatilho = volume (KPI2 > 50 %) E persistência (janela de 5).",
     F_REG, 13, INK)
text(MX + 16, CT - 20,
     "Nada é enviado a um RIC real e nenhuma configuração de rede é alterada — mesmo formato do decision.json do lab.",
     F_IT, 11, MUTED)
img(FIG / "fluxo.png", MX + 8, CT - 40, PW - 2 * MX - 16, 300, align="c")

# ---- 15 limitações ----
new_page("Limitações", "O que estes números não dizem")
bullets(MX + 16, CT + 4, [
    "RFSIM não é rede real — resultados não generalizam para rede comercial.",
    "DRB.RlcSduDelayDl é proxy técnico de latência, não MOS de aplicativo reportado por usuário.",
    "Poucos UEs — agregação por fase é didática, não estatística de campus.",
    "Ponto de limiar numericamente instável (CV ~48 %), mas decisão robusta pela zona morta; trocar o critério por um limiar da cauda alta mudaria as conclusões.",
    "baseline 25 % não é ruído: são 5 rajadas ativas reais (137–218 µs) já em patamar de carga.",
    "recovery não voltou totalmente ao normal — cauda de 390 e 470 µs, acima do pico de stress.",
    "Amostras ociosas contam como \"sem degradação\" no KPI 2 sobre Sf — por isso reportamos KPI2_ativo.",
    "Política A1 é simulada (dry-run); gatilho exige volume e persistência para não atuar por pico isolado.",
], gap=24, size=12.8, width_chars=96)

# ---- 16 conclusão ----
new_page("Conclusão", "O que os dados sustentam")
y = bullets(MX + 16, CT, [
    "Há degradação de latência sustentada e inequívoca durante stress (100 % das amostras e 56/56 janelas acima de L).",
    "baseline e recovery não apresentam degradação sustentada; porém baseline contém rajadas relevantes e recovery não normalizou completamente a cauda.",
    "O limiar foi escolhido, testado por sensibilidade e bootstrap, e a decisão que ele gera não depende do valor exato.",
    "A recomendação A1 é específica, condicionada a duas evidências, e permanece em dry-run.",
], gap=30, size=13.5, width_chars=98)
card(MX + 16, 84, PW - 2 * MX - 32, 74)
text(MX + 44, 132, "Reprodutível", F_SB, 13, ACCENT)
text(MX + 44, 108, "menu Kernel > Restart & Run All no notebook_g3_latencia.ipynb chega aos mesmos números e gráficos.", F_REG, 12, INK)
text(MX + 44, 90, "Este PDF é gerado por apresentacao/gerar_apresentacao.py a partir do mesmo dataset.", F_IT, 10.5, MUTED)
footer(); c.showPage()
c.save()
print("\nPDF:", PDF_OUT, f"({PDF_OUT.stat().st_size/1024:.0f} KB)")
