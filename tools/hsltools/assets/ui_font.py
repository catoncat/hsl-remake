"""Cut the remake's readable UI font out of Noto Sans SC.

The 重製選項 page and the OPT-FONT improved value draw with a bundled sans font, because a
browser offers Godot no system font. The font is Noto Sans SC Medium (SIL OFL 1.1, the
notofonts/noto-cjk SubsetOTF build) cut down to the characters the game can show: every glyph
of the original bitmap fonts (they bound what the original text can draw), the printable ASCII
row, the bitmap fonts' half-width aliases, both sides of the simplified display table and every
character in the string values of content/authored/ (the remake's own texts: option cards,
sequel levels). Output and license sit in game/assets/fonts/.

Maintainer tool, run again only when one of those inputs gains a character:

    pip install fonttools brotli
    python3 tools/hsltools/assets/ui_font.py SOURCE_OTF

SOURCE_OTF is NotoSansSC-Medium.otf from
https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/SC/NotoSansSC-Medium.otf
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "game/assets/fonts/NotoSansSC-UI.woff2"
BITMAP_TABLE = ROOT / "content/generated/hsl/fonts/original_fonts.json"
SIMPLIFIED_TABLE = ROOT / "content/generated/hsl/text/simplified_chars.json"
AUTHORED = ROOT / "content/authored"


def _strings(value: object) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [text for key, item in value.items() for text in [str(key), *_strings(item)]]
    if isinstance(value, list):
        return [text for item in value for text in _strings(item)]
    return []


def characters() -> str:
    bitmap = json.loads(BITMAP_TABLE.read_text(encoding="utf-8"))
    chars = set(bitmap["chars"]) | {chr(code) for code in range(0x20, 0x7F)} | set(bitmap["half_aliases"])
    simplified = json.loads(SIMPLIFIED_TABLE.read_text(encoding="utf-8"))
    for source, shown in simplified["chars"].items():
        chars |= set(source) | set(shown)
    for choice in simplified["remake_choices"].values():
        chars |= set(choice["shows"])
    tracked = subprocess.run(["git", "-C", str(ROOT), "ls-files", "content/authored/*.json", "content/authored/**/*.json"],
                             capture_output=True, text=True, check=True).stdout.split()
    for path in tracked:
        for text in _strings(json.loads((ROOT / path).read_text(encoding="utf-8"))):
            chars |= set(text)
    return "".join(sorted(char for char in chars if char.isprintable()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path, help="NotoSansSC-Medium.otf")
    args = parser.parse_args()
    from fontTools import subset

    text = characters()
    options = subset.Options()
    options.flavor = "woff2"
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.notdef_outline = True
    font = subset.load_font(str(args.source), options)
    subsetter = subset.Subsetter(options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    subset.save_font(font, str(OUTPUT), options)
    print(f"UI_FONT chars={len(text)} bytes={OUTPUT.stat().st_size} out={OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
