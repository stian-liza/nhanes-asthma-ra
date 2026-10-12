"""Build a concise Word report from audited CSVs; never fit or change models.

Run from the repository root with --code-ref set to the published commit SHA.
Dependencies: python-docx, reportlab, Poppler; pass --font-path for a CJK TTF.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.opc.constants import RELATIONSHIP_TYPE as RT
from figures import rows

REPO = "https://github.com/stian-liza/nhanes-asthma-ra"
FONT = "Arial Unicode MS"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--code-ref", required=True)
    ap.add_argument("--source", type=Path, default=Path("outputs/pooled_only_20261012_v03"))
    ap.add_argument("--output", type=Path, default=Path("outputs/client_report_20261012_v03"))
    ap.add_argument("--font-path", type=Path, default=Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf"))
    args = ap.parse_args()
    source, out = args.source, args.output
    out.mkdir(parents=True, exist_ok=True)
    assert json.loads((source / "run_gate.json").read_text())["verdict"] == "pass"
    assert json.loads((source / "review/review_gate.json").read_text())["verdict"] == "pass"
    reg = rows(source / "regression.csv")
    prev = {r["group"]: r for r in rows(source / "asthma_prevalence.csv")}
    interaction = {r["variable"]: r for r in rows(source / "interaction_tests.csv")}
    review = json.loads((source / "review/review_gate.json").read_text())
    char = {(r["group"], r["variable"], r["level"]): r for r in rows(source / "characteristics.csv")}
    m3 = reg[-1]
    subprocess.run([
        "Rscript", "scripts/client_report_v03/figures.R",
        str(source), str(out / "figures")
    ], check=True)
    links = []
    doc = Document(); sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(21), Cm(29.7)
    sec.top_margin, sec.bottom_margin = Cm(1.65), Cm(1.6)
    sec.left_margin = sec.right_margin = Cm(1.8)
    sec.header_distance = sec.footer_distance = Cm(.7)
    for st in doc.styles:
        for border in st.element.xpath('.//w:pBdr'):
            border.getparent().remove(border)
    for name, size in [("Normal", 10.5), ("Title", 18), ("Subtitle", 10.5),
                       ("Heading 1", 12), ("Heading 2", 11)]:
        st = doc.styles[name]; st.font.name = FONT; st.font.size = Pt(size)
        st.font.color.rgb = RGBColor(0, 0, 0)
        st.font.italic = False
        st.element.get_or_add_rPr().get_or_add_rFonts().set(qn("w:eastAsia"), FONT)
        st.paragraph_format.line_spacing = 1.18
        st.paragraph_format.space_after = Pt(5)
        if name.startswith("Heading"):
            st.font.bold = True; st.paragraph_format.space_before = Pt(8)
    for name in ("Title", "Subtitle"):
        doc.styles[name].paragraph_format.space_before = Pt(0)
    doc.core_properties.title = "类风湿关节炎与曾患哮喘的关联分析报告"
    doc.core_properties.author = ""
    doc.core_properties.subject = "NHANES统一加权横断面分析"
    footer = sec.footer.paragraphs[0]; footer.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    rr = footer.add_run("NHANES 统一分析  |  "); rr.font.size = Pt(8)
    fld = OxmlElement("w:fldSimple"); fld.set(qn("w:instr"), "PAGE"); footer._p.append(fld)
    footer.add_run(" / 3").font.size = Pt(8)

    def p(text="", small=False):
        pp = doc.add_paragraph(text)
        if small:
            for run in pp.runs: run.font.size = Pt(9)
            pp.paragraph_format.space_after = Pt(4)
        return pp

    def hyperlink(pp, label, url):
        rel = pp.part.relate_to(url, RT.HYPERLINK, is_external=True)
        h = OxmlElement("w:hyperlink"); h.set(qn("r:id"), rel)
        r = OxmlElement("w:r"); rp = OxmlElement("w:rPr")
        ff = OxmlElement("w:rFonts"); ff.set(qn("w:ascii"), FONT); ff.set(qn("w:eastAsia"), FONT); rp.append(ff)
        color = OxmlElement("w:color"); color.set(qn("w:val"), "245774"); rp.append(color)
        under = OxmlElement("w:u"); under.set(qn("w:val"), "single"); rp.append(under)
        size = OxmlElement("w:sz"); size.set(qn("w:val"), "18"); rp.append(size)
        r.append(rp); t = OxmlElement("w:t"); t.text = label; r.append(t); h.append(r); pp._p.append(h)
        links.append({"label": label, "url": url})

    def code_url(file, start=None, end=None):
        text = f"{REPO}/blob/{args.code_ref}/{file}"
        if start:
            lines = Path(file).read_text().splitlines()
            assert 1 <= start <= len(lines) and (end is None or start <= end <= len(lines))
            text += f"#L{start}" + (f"-L{end}" if end else "")
        return text

    def step(title, specs):
        doc.add_paragraph(title, "Heading 1")
        pp = p(small=True)
        for i, (label, file, start, end) in enumerate(specs):
            if i: pp.add_run("   ")
            hyperlink(pp, label, code_url(file, start, end))
        pp.paragraph_format.keep_with_next = True

    def figure(stem, caption):
        pp = p(); pp.paragraph_format.space_after = Pt(2)
        pp.add_run().add_picture(str(out / "figures" / f"{stem}.png"), width=Cm(17.1))
        inline = pp._p.xpath('.//wp:docPr')[0]; inline.set("descr", caption)
        p(caption, small=True)

    def table(headers, body, widths):
        t = doc.add_table(rows=1, cols=len(headers)); t.alignment = WD_TABLE_ALIGNMENT.CENTER; t.autofit = False
        for i, w in enumerate(widths): t.columns[i].width = Cm(w)
        for i, h in enumerate(headers): t.rows[0].cells[i].text = h
        for data in body:
            for cell, value in zip(t.add_row().cells, data): cell.text = str(value)
        for i, row in enumerate(t.rows):
            trpr = row._tr.get_or_add_trPr(); no_split = OxmlElement("w:cantSplit"); trpr.append(no_split)
            if i == 0: trpr.append(OxmlElement("w:tblHeader"))
            for j, cell in enumerate(row.cells):
                cell.width = Cm(widths[j]); cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
                pr = cell._tc.get_or_add_tcPr()
                borders = OxmlElement("w:tcBorders")
                for edge in ("top", "left", "bottom", "right"):
                    e = OxmlElement("w:" + edge); e.set(qn("w:val"), "single"); e.set(qn("w:sz"), "4"); e.set(qn("w:color"), "D9D9D9"); borders.append(e)
                pr.append(borders)
                margins = OxmlElement("w:tcMar")
                for edge in ("top", "bottom", "left", "right"):
                    e = OxmlElement("w:" + edge); e.set(qn("w:w"), "75"); e.set(qn("w:type"), "dxa"); margins.append(e)
                pr.append(margins)
                if i == 0:
                    shade = OxmlElement("w:shd"); shade.set(qn("w:fill"), "E7EFF4"); pr.append(shade)
                for para in cell.paragraphs:
                    para.alignment = WD_ALIGN_PARAGRAPH.LEFT if j == 0 else WD_ALIGN_PARAGRAPH.CENTER
                    para.paragraph_format.space_after = Pt(0); para.paragraph_format.line_spacing = 1.12
                    for run in para.runs:
                        run.font.size = Pt(10); run.font.bold = i == 0
        p().paragraph_format.space_after = Pt(0)
        return t

    # PAGE ONE — question, definitions, and cohort.
    doc.add_paragraph("类风湿关节炎与曾患哮喘的关联", "Title")
    doc.add_paragraph("NHANES 截至2023年可用数据统一分析报告", "Subtitle")
    p(f"结果摘要　纳入{review['n']:,}人。调整预设因素后，类风湿关节炎与曾患哮喘呈正向关联；比值比为{float(m3['OR']):.2f}，95%置信区间为{float(m3['lower']):.2f}至{float(m3['upper']):.2f}。尚无充分证据说明关联强度随年龄或性别不同。")
    step("1 研究问题与数据范围", [("输入与权重核对代码", "scripts/pooled_only_v3/config.R", 30, 81)])
    p("比较类风湿关节炎者与明确无关节炎者的曾患哮喘比例及调整后关联。合并1999—2016常规数据、2017—2020年3月特殊发布数据及2021年8月—2023年8月数据，共11个发布块；统一分析，不做分时期比较或周期调整。调查中断时段没有观测。")
    step("2 疾病定义与样本筛选", [("疾病定义代码", "scripts/year_extension_v1/prepare.R", 62, 79),
                                ("筛选复核代码", "scripts/pooled_only_v3/review_results.R", 29, 75),
                                ("流程图代码", "scripts/client_report_v03/figures.R", 30, 76)])
    p("曾患哮喘依据问卷自报曾被医生或其他卫生专业人员告知患哮喘；类风湿关节炎依据自报关节炎及其类型。对照须明确无关节炎，其他类型及状态不明者不纳入。分析限20至79岁、抽样设计有效且协变量完整者。")
    figure("sample_flow", "图1　样本筛选流程　人数为实际样本数，排除按图示顺序进行。")
    p(f"最终包括类风湿关节炎{review['cases']:,}人和明确无关节炎{review['controls']:,}人。协变量不完整排除{review['excluded_incomplete']:,}人，占疾病资格人群的{100*review['excluded_incomplete']/review['pre_covariate_n']:.2f}%；本次未进行多重插补。", small=True)

    # PAGE TWO — only results needed to answer the primary question.
    doc.add_page_break()
    step("3 加权描述与组间比较", [("抽样设计代码", "scripts/pooled_only_v3/analyze.R", 25, 60),
                                ("描述与分类检验代码", "scripts/pooled_only_v3/analyze.R", 75, 227)])
    p("使用体检抽样权重、分层和抽样单位，在完整病例子人群中估计比例。下表人数未经加权，比例及95%置信区间经过加权。")
    body = []
    for key, label in [("No_arthritis", "明确无关节炎"), ("RA", "类风湿关节炎")]:
        rr = prev[key]
        body.append([label, f"{int(rr['n']):,}", f"{int(rr['events']):,}",
                     f"{100*float(rr['estimate']):.2f}%\n（{100*float(rr['lower']):.2f}%—{100*float(rr['upper']):.2f}%）"])
    p("表1　两组曾患哮喘的加权比例", small=True)
    table(["比较人群", "实际人数", "曾患哮喘人数", "加权比例\n（95%置信区间）"], body, [4.2, 2.5, 3.2, 7.1])
    age0 = float(char['No_arthritis', 'age', 'continuous']['estimate']); age1 = float(char['RA', 'age', 'continuous']['estimate'])
    p(f"类风湿关节炎组的曾患哮喘比例较高。两组基本构成也有差异，例如加权平均年龄分别为{age1:.2f}岁与{age0:.2f}岁，因此进一步按预设因素进行调整。")
    p("完整一般特征及协变量分类比较结果另见随附补充表。", small=True)
    p("分类比较采用Rao–Scott校正，考察类别间疾病比例的总体差异；这些检验不能证明独立作用，也不用于选择调整变量。", small=True)
    step("4 调整其他因素后的关联", [("四模型设定代码", "scripts/pooled_only_v3/config.R", 15, 20),
                                   ("加权回归代码", "scripts/pooled_only_v3/analyze.R", 229, 382),
                                   ("四模型森林图代码", "scripts/client_report_v03/figures.R", 78, 111)])
    p(f"采用复杂抽样加权Logistic回归，报告比值比（OR）及95%置信区间。四个模型均使用同一批{review['n']:,}人；方差采用Taylor线性化，推断使用方案指定的设计自由度。")
    figure("model_forest", "图2　四个模型中类风湿关节炎与曾患哮喘的关联　方块为比值比，横线为95%置信区间；虚线为1，横轴为对数刻度。")
    p("完全调整后仍观察到正向关联。比值比反映曾患哮喘的优势之比，不能直接解释为新发哮喘风险的倍数，也不能据此确定因果方向。")

    # PAGE THREE — prespecified subgroups and scientific limits.
    doc.add_page_break()
    step("5 年龄与性别亚组", [("亚组与交互检验代码", "scripts/pooled_only_v3/analyze.R", 384, 436),
                            ("分开绘制森林图代码", "scripts/client_report_v03/figures.R", 113, 153)])
    figure("age_forest", "图3　年龄亚组的调整后关联　年龄交互P=" + f"{float(interaction['agegroup']['p']):.4f}。")
    figure("sex_forest", "图4　性别亚组的调整后关联　性别交互P=" + f"{float(interaction['sex']['p']):.4f}。")
    p("各亚组内均观察到正向关联，但尚无充分证据认定关联强度随年龄组或性别改变。")
    p("年龄亚组仍调整组内具体年龄及其余因素；性别亚组调整其余六项因素。交互检验比较关联强度，不是比较各组P值是否显著。", small=True)
    step("6 结论与解释边界", [("模型诊断代码", "scripts/pooled_only_v3/diagnose.R", 52, 146),
                              ("独立数值复核代码", "scripts/pooled_only_v3/review_results.R", 87, 176)])
    p("本研究纳入人群中，自报类风湿关节炎与曾患哮喘呈正向统计关联。11个模型的数值诊断及65项复核通过，支持本次实现与结果的一致性。")
    p("解释需保留三点限制。第一，横断面和自报诊断无法判断发病先后、确立因果或验证机制；对照仅为明确无关节炎者。第二，完整病例排除可能引入选择偏倚，本次未做插补、替代表型或其他敏感性分析。第三，跨调查空档合并的适用性未获本研究验证，且未调整时间相关混杂。")
    pp = p("CDC通常不建议将2021—2023与早期周期直接合并。本结果限于预设权重下已观测时段的混合人群关联，不代表连续完整时期的总体估计。依据：", small=True)
    hyperlink(pp, "CDC权重指导", "https://wwwn.cdc.gov/nchs/nhanes/tutorials/weighting.aspx")
    pp.add_run("；"); hyperlink(pp, "2021—2023分析指南", "https://wwwn.cdc.gov/nchs/nhanes/continuousnhanes/OverviewBrief.aspx?Cycle=2021-2023")
    pp = p("复现入口：", small=True)
    hyperlink(pp, "本次统一分析入口", code_url("scripts/pooled_only_v3/run_analysis.sh", 1, 22))
    pp.add_run("；"); hyperlink(pp, "报告生成代码", code_url("scripts/client_report_v03/build_report.py"))
    p(f"结果版本 v03　代码提交 {args.code_ref[:12]}　分析日期 2026年10月12日", small=True)

    doc.save(out / "NHANES_类风湿关节炎与曾患哮喘_分析报告.docx")
    (out / "links.json").write_text(json.dumps(links, ensure_ascii=False, indent=2))
    used = [source / x for x in ["regression.csv", "asthma_prevalence.csv", "subgroups.csv", "interaction_tests.csv", "characteristics.csv", "review/review_gate.json", "review/sample_flow.csv"]]
    (out / "report_source_bindings.json").write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in used}, indent=2))
    print(out / "NHANES_类风湿关节炎与曾患哮喘_分析报告.docx")


if __name__ == "__main__":
    main()
