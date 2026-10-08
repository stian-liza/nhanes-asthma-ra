"""Correct Quartz CFF GID-to-CID ToUnicode mappings without changing drawn glyphs.
Run after redraw_figures_v03.R. Requires pypdf and fonttools.
"""
from pathlib import Path
import re
import argparse
import unicodedata
from fontTools.ttLib import TTFont
from pypdf import PdfReader, PdfWriter
from pypdf.generic import DecodedStreamObject, NameObject, BooleanObject
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser()
parser.add_argument('--figure-dir',default='outputs/figure_revision_20261008_v03')
args=parser.parse_args()
figure_dir=root/args.figure_dir
fonts={w:TTFont(root/f'assets/fonts/source-han-sans-cn/SourceHanSansCN-{w}.otf') for w in ('Regular','Medium')}
fixed=0
for path in sorted(figure_dir.rglob('*.pdf')):
    reader=PdfReader(path);writer=PdfWriter();writer.clone_document_from_reader(reader)
    changed=False
    for page in writer.pages:
        for ref in page['/Resources']['/Font'].values():
            pdf_font=ref.get_object();base=str(pdf_font['/BaseFont'])
            if 'SourceHanSansCN-' not in base or pdf_font.get('/NHANESMapFixed'):continue
            weight=base.split('SourceHanSansCN-')[1];font=fonts[weight]
            old=pdf_font['/ToUnicode'].get_data().decode('ascii')
            pairs=[]
            for block in re.findall(r'beginbfrange(.*?)endbfrange',old,re.S):
                for a,b,u in re.findall(r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>',block):
                    for gid in range(int(a,16),int(b,16)+1):
                        code=int(u,16)+gid-int(a,16);glyph=font.getBestCmap()[code]
                        assert font.getGlyphID(glyph)==gid,(path,code,glyph,gid)
                        cid=int(glyph.removeprefix('cid'))
                        char=chr(code)
                        if 0x2e80<=code<=0x2fff:char=unicodedata.normalize('NFKC',char)
                        pairs.append((cid,char.encode('utf-16-be').hex()))
            assert pairs
            text='/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<0000><FFFF>\nendcodespacerange\n'
            for start in range(0,len(pairs),100):
                chunk=pairs[start:start+100];text+=f'{len(chunk)} beginbfchar\n'
                text+=''.join(f'<{cid:04x}><{u}>\n' for cid,u in chunk)+'endbfchar\n'
            text+='endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n'
            stream=DecodedStreamObject();stream.set_data(text.encode('ascii'))
            pdf_font[NameObject('/ToUnicode')]=writer._add_object(stream)
            pdf_font[NameObject('/NHANESMapFixed')]=BooleanObject(True);changed=True
    if changed:
        writer.write(path);fixed+=1
print(f'Corrected Chinese text extraction in {fixed} vector PDFs; drawing streams unchanged.')
