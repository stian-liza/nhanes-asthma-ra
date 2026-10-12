"""Source-bound vector figures for the three-page Chinese pooled report."""
import csv
import math
import subprocess
from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.colors import HexColor


def rows(path):
    with Path(path).open(encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def draw_figures(source, destination, font_path):
    destination.mkdir(parents=True, exist_ok=True)
    pdfmetrics.registerFont(TTFont("ReportCN", str(font_path)))
    flow = {r["step"]: r for r in rows(source / "review/sample_flow.csv")}
    subgroups = rows(source / "subgroups.csv")
    blue, gray = HexColor("#245774"), HexColor("#555555")

    # SAMPLE FLOW: keep sequential exclusions separate from overlapping missingness.
    path = destination / "sample_flow.pdf"
    c = canvas.Canvas(str(path), pagesize=(480, 242))
    steps = ["All_DEMO", "age_20_79", "valid_MEC_design", "known_ever_asthma",
             "RA_or_explicit_no_arthritis", "smoking"]
    labels = ["全部人口学记录", "年龄20至79岁", "体检抽样设计有效", "曾患哮喘状态明确",
              "疾病状态符合比较要求", "最终完整病例"]
    reasons = ["年龄不符合", "权重或抽样设计无效", "哮喘状态不明",
               "其他关节炎或关节炎状态不明", "协变量不完整"]
    for i, (step, label) in enumerate(zip(steps, labels)):
        y = 208 - 40 * i
        c.setFillColor(HexColor("#EEF4F7") if i == 5 else HexColor("#FAFBFC"))
        c.setStrokeColor(HexColor("#B8C9D2"))
        c.roundRect(6, y, 267, 29, 4, fill=1)
        c.setFillColor(HexColor("#111111")); c.setFont("ReportCN", 10.4)
        c.drawCentredString(139.5, y + 10, f"{label}  {int(flow[step]['remaining']):,}人")
        if i < 5:
            c.setStrokeColor(blue); c.setFillColor(blue)
            c.line(139.5, y, 139.5, y - 10)
            c.line(139.5, y - 10, 136.5, y - 6)
            c.line(139.5, y - 10, 142.5, y - 6)
            excluded = int(flow[steps[i]]["remaining"]) - int(flow[steps[i+1]]["remaining"])
            c.line(273, y + 2, 285, y + 2)
            c.setFillColor(gray); c.setFont("ReportCN", 9.3)
            c.drawString(291, y + 4, reasons[i])
            c.drawString(291, y - 9, f"排除 {excluded:,}人")
    c.showPage(); c.save()

    # FOREST: all five estimates and intervals come directly from the new result CSV.
    path = destination / "subgroup_forest.pdf"
    c = canvas.Canvas(str(path), pagesize=(480, 227))
    c.setFont("ReportCN", 10); c.setFillColor(HexColor("#111111"))
    c.drawString(8, 210, "亚组"); c.drawRightString(164, 210, "实际人数")
    c.drawRightString(474, 210, "比值比（95%置信区间）")
    x0, x1 = 194, 327
    def xpos(v):
        return x0 + (math.log(v) - math.log(.8)) / (math.log(4) - math.log(.8)) * (x1 - x0)
    c.setStrokeColor(HexColor("#888888")); c.setDash(3, 3)
    c.line(xpos(1), 34, xpos(1), 197); c.setDash()
    names = ["20至39岁", "40至59岁", "60至79岁", "男性", "女性"]
    ys = [185, 155, 125, 82, 52]
    for row, label, y in zip(subgroups, names, ys):
        c.setFillColor(HexColor("#111111")); c.setFont("ReportCN", 10)
        c.drawString(8, y - 3, label); c.drawRightString(164, y - 3, f"{int(row['n']):,}")
        lo, hi, estimate = (float(row[k]) for k in ("lower", "upper", "OR"))
        c.drawRightString(474, y - 3, f"{estimate:.2f}（{lo:.2f}—{hi:.2f}）")
        c.setStrokeColor(blue); c.setFillColor(blue); c.setLineWidth(1.3)
        c.line(xpos(lo), y, xpos(hi), y)
        for v in (lo, hi): c.line(xpos(v), y - 3, xpos(v), y + 3)
        c.rect(xpos(estimate) - 3, y - 3, 6, 6, fill=1, stroke=0)
    c.setStrokeColor(HexColor("#999999")); c.setLineWidth(.6); c.line(x0, 27, x1, 27)
    c.setFont("ReportCN", 9); c.setFillColor(gray)
    for v in [1, 1.5, 2, 3, 4]:
        c.line(xpos(v), 27, xpos(v), 24); c.drawCentredString(xpos(v), 12, f"{v:g}")
    c.showPage(); c.save()
    for stem in ("sample_flow", "subgroup_forest"):
        subprocess.run(["pdftoppm", "-r", "220", "-png", "-singlefile",
                        str(destination / f"{stem}.pdf"), str(destination / stem)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

