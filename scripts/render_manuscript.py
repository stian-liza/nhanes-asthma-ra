"""Render the report with the supplied document renderer and explicit CJK fonts.

Usage: python scripts/render_manuscript.py --renderer /path/to/render_docx.py
       --qa-dir /path/to/temporary/rendered-pages
The final PDF is copied beside the DOCX only after a successful render.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from xml.sax.saxutils import escape

ROOT=Path(__file__).resolve().parents[1]
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--renderer',type=Path,required=True)
    ap.add_argument('--qa-dir',type=Path,required=True);args=ap.parse_args()
    doc=ROOT/'reports/manuscript/nhanes_asthma_ra_report_3fig4table_v03.docx'
    with tempfile.TemporaryDirectory(prefix='nhanes-fontconfig-') as td:
        env=os.environ.copy()
        if sys.platform=='darwin':
            dirs=[Path('/System/Library/Fonts'),Path('/System/Library/Fonts/Supplemental')]
            bundled=(Path(sys.executable).parent.parent.parent/'native/libreoffice-headless/libreoffice/LibreOfficeDev.app/Contents/Resources/fonts/truetype')
            if bundled.exists():dirs.append(bundled)
            cfg=Path(td)/'fonts.conf'
            cfg.write_text('<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd"><fontconfig>'+
                           ''.join('<dir>'+escape(str(d))+'</dir>' for d in dirs)+
                           '<cachedir>'+escape(td+'/cache')+'</cachedir></fontconfig>')
            env['FONTCONFIG_FILE']=str(cfg)
        subprocess.run([sys.executable,str(args.renderer),str(doc),'--output_dir',str(args.qa_dir),'--emit_pdf'],env=env,check=True)
    result=args.qa_dir/(doc.stem+'.pdf')
    shutil.copy2(result,doc.with_suffix('.pdf'))
    print('Rendered PDF copied to',doc.with_suffix('.pdf'))

if __name__=='__main__':main()
