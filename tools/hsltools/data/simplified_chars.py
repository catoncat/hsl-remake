"""The per-character table the remake uses to display text the way the original font draws it.

The original stores text as Big5 traditional and shows simplified because its bitmap fonts draw
simplified glyphs at traditional codes (docs/evidence_packets/static_reverse/original_font_script/).
The remake keeps the traditional source text and converts at one display seam
(game/text/SimplifiedDisplayTranslation.gd) with this table: for every traditional-only
character (an OpenCC TSCharacters key) whose FONT.24 glyph was reviewed, the character the
original draws there.

Inputs: glyph_review.json (resource-derived reading of the original glyphs) and the vendored
OpenCC TSCharacters.txt (candidate forms only). A character the review keeps traditional (後 於 …)
maps to itself and is listed in kept_traditional; the few remake choices (職 font bug, 噁 outside
the system font, the three unresolved glyphs, 絶 outside Big5) are listed with their reason.

Registry task simplified_chars (family data): output content/generated/hsl/text/simplified_chars.json.
"""
from __future__ import annotations

import json
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import Context, GeneratedFilesTask

OUT = Path('content/generated/hsl/text/simplified_chars.json')
REVIEW = Path('docs/evidence_packets/static_reverse/original_font_script/glyph_review.json')
OPENCC_TS = Path('tools/hsltools/data/opencc/TSCharacters.txt')


def opencc_candidates(root: Path) -> dict[str, list[str]]:
    table: dict[str, list[str]] = {}
    for line in (root / OPENCC_TS).read_text(encoding='utf-8').splitlines():
        if line.strip():
            traditional, candidates = line.split('\t')
            table[traditional] = candidates.split(' ')
    return table


def traditional_only(candidates: dict[str, list[str]]) -> set[str]:
    """OpenCC keys whose first simplified candidate is a different character."""
    return {char for char, forms in candidates.items() if forms[0] != char}


def build(root: Path) -> dict:
    review = json.loads((root / REVIEW).read_text(encoding='utf-8'))
    candidates = opencc_candidates(root)
    chars: dict[str, str] = {}
    for char in review['drawn_as_opencc_first']:
        chars[char] = candidates[char][0]
    for char, drawn in review['drawn_as_other_candidate'].items():
        chars[char] = drawn  # 囉 is drawn 罗, outside the OpenCC candidates: the original font decides
    remake_choices: dict[str, dict[str, str]] = {}
    for group in ('slot_swapped', 'not_representable'):
        for char, entry in review[group].items():
            chars[char] = candidates[char][0]
            remake_choices[char] = {'shows': candidates[char][0], 'original_draws': entry['drawn'], 'reason': entry['note']}
    for group in ('unresolved', 'no_big5_slot'):
        for char, note in review[group].items():
            chars[char] = candidates[char][0]
            remake_choices[char] = {'shows': candidates[char][0], 'original_draws': '', 'reason': note}
    kept = review['drawn_traditional']
    overlap = set(kept) & set(chars)
    if overlap:
        raise ValueError(f'kept traditional and converted at once: {"".join(sorted(overlap))}')
    trad = traditional_only(candidates)
    bad = [f'{char}→{shown}' for char, shown in chars.items() if len(shown) != 1 or ord(shown) > 0xFFFF or shown in trad]
    if bad:
        raise ValueError('display forms must be one BMP character that is not traditional-only (the 1:1 mapping keeps string indexes): ' + ' '.join(bad))
    return {
        'schema': 'hsl_simplified_chars.v1',
        'evidence_tier': 'resource-derived',
        'claim': 'The character the original FONT.24 draws for each reviewed traditional-only character; '
                 'kept_traditional are drawn traditional by the original font; remake_choices are the remake-invented exceptions.',
        'sources': [REVIEW.as_posix(), OPENCC_TS.as_posix()],
        'seam': 'game/text/SimplifiedDisplayTranslation.gd',
        'chars': dict(sorted(chars.items())),
        'kept_traditional': kept,
        'remake_choices': dict(sorted(remake_choices.items())),
    }


class SimplifiedCharsTask(GeneratedFilesTask):
    name = 'simplified_chars'
    family = 'data'
    inputs = (REVIEW.as_posix(), OPENCC_TS.as_posix())
    outputs = (OUT.as_posix(),)
    scripts = ('tools/hsltools/data/simplified_chars.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.as_posix(): json_bytes(build(ctx.root))}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        payload = json.loads(rendered[OUT.as_posix()])
        return (f'SIMPLIFIED_CHARS_PASS chars={len(payload["chars"])} kept_traditional={len(payload["kept_traditional"])} '
                f'remake_choices={len(payload["remake_choices"])}')


def tasks() -> list[SimplifiedCharsTask]:
    return [SimplifiedCharsTask()]
