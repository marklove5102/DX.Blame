"""Generate BMP bitmaps from the DX.Blame SVG icons for Delphi IDE splash and about screens.

Uses Inkscape for faithful SVG rendering, then Pillow for PNG-to-BMP conversion.
Small sizes (<=32) use a simplified SVG with bolder, fewer elements for readability.
"""
import subprocess
import os
from PIL import Image

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SVG_FULL = os.path.join(SCRIPT_DIR, "logos", "dx-blame-icon.svg")
SVG_SMALL = os.path.join(SCRIPT_DIR, "logos", "dx-blame-icon-small.svg")
INKSCAPE = r"C:\Program Files\Inkscape\bin\inkscape.exe"

# (name, size, svg_source)
TARGETS = [
    ("DX.Blame.SplashIcon", 24, SVG_SMALL),
    ("DX.Blame.Icon32",     32, SVG_SMALL),
    ("DX.Blame.Icon48",     48, SVG_FULL),
    ("DX.Blame.Icon64",     64, SVG_FULL),
    ("DX.Blame.Icon128",   128, SVG_FULL),
]

for name, size, svg_path in TARGETS:
    png_path = os.path.join(SCRIPT_DIR, f"{name}.png")
    bmp_path = os.path.join(SCRIPT_DIR, f"{name}.bmp")

    subprocess.run([
        INKSCAPE,
        svg_path,
        "--export-type=png",
        f"--export-filename={png_path}",
        f"--export-width={size}",
        f"--export-height={size}",
    ], check=True, capture_output=True)

    img = Image.open(png_path).convert("RGB")
    img.save(bmp_path, "BMP")
    os.remove(png_path)

    src = "small" if svg_path == SVG_SMALL else "full"
    print(f"  {name}.bmp ({size}x{size}) [{src}]")

print("Done.")
