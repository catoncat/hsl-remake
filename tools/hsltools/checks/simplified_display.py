"""Player-visible text is displayed simplified, the way the original font draws it.

The remake keeps its player copy in traditional characters (the original Big5 source text; see
content:player_copy_traditional) and converts at one display seam with
content/generated/hsl/text/simplified_chars.json. This check proves the displayed form:

  strings  every player-visible string (the exact scope of content:player_copy_traditional)
           passed through the table carries no traditional-only character (an OpenCC
           TSCharacters key) other than the ones the original font itself draws traditional
           (kept_traditional). A traditional-only character without a table entry fails: read
           its original glyph (`PYTHONPATH=tools python3 -m hsltools.sources.original_font show X`),
           add it to glyph_review.json and `python3 tools/hsl.py generate simplified_chars`.
  images   every image of the baked-text inventory
           (docs/evidence_packets/static_reverse/original_font_script/image_inventory.json) still
           has its recorded pixel hash (rgba_sha256, png_sha256: the original-derived manifest's value;
           a player's Pillow / zlib encodes the same image to other bytes), and an image whose baked
           text is traditional is either replaced (its `simplified_replacement` exists and is recorded) or carries a `kept` reason.
           The credits redraw is also checked cell by cell (workteam_simplified.check_cells): the
           characters both scripts share keep the shape's lettering pixel for pixel, every redrawn
           cell has ink.

Command line: `PYTHONPATH=tools python3 -m hsltools.checks.simplified_display inventory` prints the
direction-neutral inventory: per file, the traditional-only and simplified-only characters of
its player-visible strings.

Registry task content:simplified_display (family content, CheckTask, replaces=()).
PASS line: SIMPLIFIED_DISPLAY_PASS strings=N traditional_only_chars=N converted=N kept=N images=N replaced=N kept_images=N.
"""
from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

from hsltools.assets.workteam_simplified import OUTPUT as WORKTEAM_REDRAW, check_cells as workteam_cell_issues
from hsltools.checks import CheckTask
from hsltools.checks.player_copy_traditional import player_strings
from hsltools.data.simplified_chars import OUT as TABLE, opencc_candidates, traditional_only
from hsltools.sources.shp import png_sha256
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context

IMAGE_INVENTORY = Path('docs/evidence_packets/static_reverse/original_font_script/image_inventory.json')


def displayed(text: str, chars: dict[str, str]) -> str:
    """The seam's conversion (game/text/SimplifiedDisplayTranslation.gd): one character for one."""
    return ''.join(chars.get(char, char) for char in text)


def check_strings(root: Path, table: dict, trad: set[str]) -> tuple[list[str], dict[str, int]]:
    chars, kept = table['chars'], set(table['kept_traditional'])
    unmapped: dict[str, list[str]] = defaultdict(list)
    seen: set[str] = set()
    counts: dict[str, int] = {}
    for location, literal in player_strings(root, counts):
        for char in displayed(literal, chars):
            if char in trad and char not in kept:
                unmapped[char].append(location)
        seen.update(char for char in literal if char in trad)
    issues = [f'{char} (no reviewed display form) in {len(places)} string(s), first {places[0]}' for char, places in sorted(unmapped.items())]
    counts['traditional_only_chars'] = len(seen)
    counts['converted'] = len(seen - kept)
    counts['kept'] = len(seen & kept)
    return issues, counts


def check_images(root: Path) -> tuple[list[str], dict[str, int]]:
    inventory = json.loads((root / IMAGE_INVENTORY).read_text(encoding='utf-8'))
    issues: list[str] = []
    counts = {'images': 0, 'replaced': 0, 'kept_images': 0}
    for entry in inventory['images']:
        counts['images'] += 1
        path = root / entry['path']
        if not path.is_file():
            issues.append(f'{entry["path"]}: missing')
            continue
        if png_sha256(path) != entry['rgba_sha256']:
            issues.append(f'{entry["path"]}: pixel hash changed — re-read its baked text and update {IMAGE_INVENTORY.as_posix()}')
        if entry['form'] != 'traditional':
            continue
        replacement = entry.get('simplified_replacement')
        if replacement:
            target = root / replacement['path']
            if not target.is_file():
                issues.append(f'{entry["path"]}: simplified replacement {replacement["path"]} missing')
            elif png_sha256(target) != replacement['rgba_sha256']:
                issues.append(f'{entry["path"]}: simplified replacement {replacement["path"]} pixel hash differs from the inventory')
            else:
                counts['replaced'] += 1
                if replacement['path'] == WORKTEAM_REDRAW.as_posix():
                    issues.extend(workteam_cell_issues(root))
        elif entry.get('kept'):
            counts['kept_images'] += 1
        else:
            issues.append(f'{entry["path"]}: bakes traditional text ({entry["glyphs"]}) with neither simplified_replacement nor a kept reason')
    return issues, counts


def check(root: Path) -> str:
    table = json.loads((root / TABLE).read_text(encoding='utf-8'))
    trad = traditional_only(opencc_candidates(root))
    string_issues, string_counts = check_strings(root, table, trad)
    image_issues, image_counts = check_images(root)
    issues = string_issues + image_issues
    if issues:
        raise ValueError(f'{len(issues)} simplified-display problem(s):\n  ' + '\n  '.join(issues))
    return (f'SIMPLIFIED_DISPLAY_PASS strings={string_counts["strings"]} traditional_only_chars={string_counts["traditional_only_chars"]} '
            f'converted={string_counts["converted"]} kept={string_counts["kept"]} images={image_counts["images"]} '
            f'replaced={image_counts["replaced"]} kept_images={image_counts["kept_images"]}')


def _big5(char: str) -> bool:
    try:
        char.encode('cp950')
    except UnicodeEncodeError:
        return False
    return True


def inventory(root: Path) -> list[str]:
    """Per file: distinct traditional-only characters (OpenCC keys with a different first form)
    and simplified-only characters (an OpenCC simplified form outside Big5) of its player strings."""
    candidates = opencc_candidates(root)
    trad = traditional_only(candidates)
    simp = {form for form in {forms[0] for forms in candidates.values()} - set(candidates) if not _big5(form)}
    by_file: dict[str, tuple[set[str], set[str]]] = defaultdict(lambda: (set(), set()))
    for location, literal in player_strings(root):
        path = location.split(':')[0].split(' ')[0]
        by_file[path][0].update(char for char in literal if char in trad)
        by_file[path][1].update(char for char in literal if char in simp)
    lines = ['file\ttraditional_only\tsimplified_only\tchars']
    total_t: set[str] = set()
    total_s: set[str] = set()
    for path, (t, s) in sorted(by_file.items()):
        total_t |= t
        total_s |= s
        if t or s:
            lines.append(f'{path}\t{len(t)}\t{len(s)}\t{"".join(sorted(t | s))[:60]}')
    lines.append(f'TOTAL files={len(by_file)} traditional_only={len(total_t)} simplified_only={len(total_s)} simplified_only_chars={"".join(sorted(total_s))}')
    return lines


class SimplifiedDisplayTask(CheckTask):
    name = 'content:simplified_display'
    family = 'content'
    inputs = ('game/', 'content/battles/', 'content/authored/', 'content/imported/', TABLE.as_posix(), IMAGE_INVENTORY.as_posix(),
              WORKTEAM_REDRAW.as_posix())
    replaces = ()  # born as a registry task
    scripts = ('tools/hsltools/checks/simplified_display.py', 'tools/hsltools/checks/player_copy_traditional.py',
               'tools/hsltools/data/simplified_chars.py', 'tools/hsltools/assets/workteam_simplified.py')

    def check(self, ctx: Context) -> str:
        try:
            return check(ctx.root)
        except (ValueError, OSError, KeyError, json.JSONDecodeError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[SimplifiedDisplayTask]:
    return [SimplifiedDisplayTask()]


if __name__ == '__main__':
    if sys.argv[1:] != ['inventory']:
        print('usage: python3 -m hsltools.checks.simplified_display inventory', file=sys.stderr)
        raise SystemExit(2)
    print('\n'.join(inventory(ROOT)))
