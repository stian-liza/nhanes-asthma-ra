"""Use the official DOCX renderer with a process-local macOS CJK font config."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from xml.sax.saxutils import escape

ap = argparse.ArgumentParser()
ap.add_argument("docx", type=Path)
ap.add_argument("--renderer", type=Path, required=True)
ap.add_argument("--output", type=Path, required=True)
args = ap.parse_args()
with tempfile.TemporaryDirectory(prefix="nhanes-report-fonts-") as temp:
    env = dict(os.environ)
    if sys.platform == "darwin":
        cfg = Path(temp) / "fonts.conf"
        directories = ["/System/Library/Fonts", "/System/Library/Fonts/Supplemental", "/Library/Fonts"]
        cfg.write_text('<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd"><fontconfig>' +
                       ''.join('<dir>' + escape(p) + '</dir>' for p in directories) +
                       '<cachedir>' + escape(temp + '/cache') + '</cachedir></fontconfig>')
        env['FONTCONFIG_FILE'] = str(cfg)
    subprocess.run([sys.executable, str(args.renderer), str(args.docx), '--output_dir',
                    str(args.output), '--emit_pdf'], env=env, check=True)
