#!/usr/bin/env python3
"""Screenshot plan for the public export (docs/internal/OPEN_SOURCE_PLAN.md §2.2, lane OSS2).

Original screenshots and recording frames move to the private archive and
public docs show remake screenshots instead. This tool lists every Markdown link to a media file and classifies
the target:

  remake             a capture of the remake (its packet header names a tests/*.gd driver)   -> keep
  original-scene     an original screen state the remake also shows                          -> remake capture (driver)
  original-measure   original frames read for pixels / timing, contact sheets, video vs native -> text + archive id
  original-resource  a render of an original resource (movie frames, SHP previews)           -> text + archive id

  python3 tools/oss_screenshots.py summary            counts per category (default)
  python3 tools/oss_screenshots.py list [--tsv PATH]  one row per link: md, line, target, category, strategy, driver
  python3 tools/oss_screenshots.py apply              copy the SAMPLES remake shots from ignored/<review>/ into
                                                      docs/screenshots/remake/ and point those links at them; the
                                                      original frame stays named as text（原版帧见私有档案：`id`）
  python3 tools/oss_screenshots.py export-text DIR    in an exported tree (tools/oss_export.sh calls this), turn every
                                                      original-measure / original-resource / not yet recaptured
                                                      original-scene link into its label plus
                                                      （原版帧见私有档案：`id`）; the private repository keeps the links

Only `apply` (docs/screenshots/remake/*.png and the linking .md files) and `export-text` (the .md files of
the given exported tree) write. The shots come from the existing
windowed capture drivers, e.g. `tools/play.sh --script res://tests/capture_title_review.gd --resolution 640x480
--screen 0`; `apply` refuses to run when a sample shot is missing. Never reads the original game.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ('.png', '.jpg', '.jpeg', '.webp', '.gif', '.mp4', '.bmp')
LINK = re.compile(r'(!?)\[([^\]]*)\]\(([^)\s]+)\)')
FENCE = re.compile(r'^\s*```')
DEST = 'docs/screenshots/remake'
RO = 'docs/evidence_packets/runtime_observations/'
REF = RO + 'original_gameplay_reference/'
TOWN = RO + 'original_world_town/'
REMAKE_LABEL = '（重制画面）'
ARCHIVE_NOTE = '原版帧见私有档案'

# Packets whose unmarked file names are still original frames (user recording, Wine capture).
ORIGINAL_PACKETS = ('menus_ui', 'effect_motion')
# Original frames read for measurement rather than shown as a screen state.
MEASURE = re.compile(r'contact_sheet|_vs_|compare|crop|diff|zoom|track|4-states|'
                     r'original_gameplay_reference/1[234]_')
REMAKE_MARKS = ('capture_', 'Godot 重制', '重制窗口化', '重制版的窗口化')
RESOURCE = re.compile(r'^content/|original_movies|shape_previews')

# original-scene: path prefix -> capture driver that shows the same remake state.
DRIVERS = (
    (REF + '01_', 'capture_title_review / capture_section_title_review'),
    (REF + '02_', 'capture_dialogue_board_review'),
    (REF + '03_', 'capture_first_battle_review'),
    (REF + '04_', 'capture_first_battle_review'),
    (REF + '05_', 'capture_system_menu_review'),
    (REF + '06_', 'capture_status_review / capture_ui_parity_review'),
    (REF + '07_', 'capture_equipment_review / capture_give_review'),
    (REF + '08_', 'capture_dialogue_selection_review'),
    (REF + '09_', 'capture_special_strip_review'),
    (REF + '10_', 'capture_combat_aftermath_review'),
    (REF + '11_', 'capture_magic_cast_review'),
    (REF + '15_', 'capture_map_pose_floaters_review'),
    (REF + '16_', 'capture_battle_reward_review'),
    (REF + '17_', 'capture_story_scene_review'),
    (REF + '18_', 'capture_campaign_handoff_review'),
    (TOWN + '01-', 'capture_world_map_review'),
    (TOWN + '02-', 'capture_system_menu_review'),
    (TOWN + '0', 'capture_town_review'),
    (TOWN + '1', 'capture_town_review / capture_party_equipment_review'),
    (RO + 'menus_ui/', 'capture_special_strip_review'),
    (RO + 'battle_0', 'same packet remake shot (first-control.png / result.png)'),
)

# Sample replacements (lane OSS2): original target -> (remake shot under ignored/, file name under DEST).
SAMPLES = {
    REF + '01_title_and_opening/frame_001.png': ('title-review/00-title-framed.png', 'title-framed.png'),
    REF + '01_title_and_opening/frame_038.png': ('section-title-review/05_name_shown.png', 'section-title-card.png'),
    REF + '02_dialogue_system/frame_004.png': ('r7-dialogue-board-review/02-369-first-page-marker.png',
                                               'dialogue-board-bottom.png'),
    REF + '05_system_scroll_menu/frame_003.png': ('system-menu-review/01-open-mission-lit.png',
                                                  'battle-system-scroll.png'),
    REF + '16_loot_spoils_screen/frame_003.png': ('battle-reward-review/initial-loot.png', 'loot-window.png'),
    REF + '17_story_events_and_victory/frame_018.png': ('system-menu-review/05-mission-card.png', 'mission-card.png'),
    TOWN + '01-bigmap-status-bar.png': ('world-map-review/01-ohm-village-start.png', 'world-map-status-bar.png'),
    TOWN + '02-bigmap-system-menu.png': ('system-menu-review/06-world-scroll-save-memoir-lit.png',
                                         'world-system-scroll.png'),
    TOWN + '05-shape-message-top.png': ('r7-dialogue-board-review/05-shape-message-top-slot.png',
                                        'dialogue-board-top.png'),
    TOWN + '06-player-message-bottom.png': ('r7-dialogue-board-review/02-369-first-page-marker.png',
                                            'dialogue-board-bottom.png'),
    TOWN + '07-shopkeeper-message-top.png': ('r7-dialogue-board-review/05-shape-message-top-slot.png',
                                             'dialogue-board-top.png'),
    TOWN + '14-town-esc-back-to-map.png': ('world-map-review/01-ohm-village-start.png', 'world-map-status-bar.png'),
    # lane OSS3 (capture_town_review fixed): the remake shows 歐姆村's menu and weapon shop in the same composition.
    TOWN + '03-town-root-menu-sidazhen.png': ('town-review/01-ohm-village-root-menu.png', 'town-root-menu.png', '重制 歐姆村 根菜单'),
    TOWN + '04-town-root-menu-amphibian-tribe.png': ('town-review/01-ohm-village-root-menu.png', 'town-root-menu.png', '重制 歐姆村 根菜单（同一构图）'),
    TOWN + '08-weapon-shop-window.png': ('town-review/03-shop-window.png', 'shop-window.png', '重制 歐姆村 武器店窗'),
    TOWN + '09-item-shop-bag-item-picked-up.png': ('town-review/05-shop-holding-bag-item.png', 'shop-holding-bag-item.png',
                                                   '重制 武器店，背包里的 長劍 拿在手上'),
}


def md_files() -> list[str]:
    out = subprocess.run(['git', '-C', str(ROOT), 'ls-files', '*.md'], capture_output=True, text=True, check=True)
    return out.stdout.split()


def packet_has_driver(target: str) -> bool:
    parts = target.split('/')
    if len(parts) < 5:
        return False
    readme = ROOT.joinpath(*parts[:4], 'README.md')
    if not readme.exists():
        return False
    head = readme.read_text(errors='ignore').splitlines()[:12]
    for line in head:
        if line.startswith('> evidence') and 'tools:' in line and '.gd' in line:
            return True
    # Older packets without a tools field say so in their first paragraph.
    return any(mark in line for line in head for mark in REMAKE_MARKS)


def classify(target: str) -> tuple[str, str, str]:
    """-> (category, strategy, driver)."""
    if target.startswith(DEST + '/'):
        return 'remake', 'keep (OSS2 sample)', ''
    if RESOURCE.search(target):
        return 'original-resource', 'text + ' + ARCHIVE_NOTE, 'players render locally from their own copy'
    packet = target.split('/')[3] if target.startswith(RO) else ''
    original = 'original' in target.lower() or packet in ORIGINAL_PACKETS
    if not original and packet_has_driver(target):
        return 'remake', 'keep (already a remake capture)', ''
    if not original:
        return 'original-measure', 'review: no remake driver in packet header', ''
    if MEASURE.search(target):
        return 'original-measure', 'text + ' + ARCHIVE_NOTE, ''
    driver = next((d for prefix, d in DRIVERS if target.startswith(prefix)), 'pick a capture driver')
    strategy = 'sample done' if target in SAMPLES else 'remake capture'
    return 'original-scene', strategy, driver


def links():
    for md in md_files():
        in_fence = False
        for lineno, line in enumerate((ROOT / md).read_text(errors='ignore').splitlines(), 1):
            if FENCE.match(line):
                in_fence = not in_fence
            if in_fence:
                continue
            for m in LINK.finditer(line):
                url = m.group(3).split('#')[0]
                if '://' in url or not url.lower().endswith(MEDIA):
                    continue
                target = os.path.normpath(os.path.join(os.path.dirname(md), url))
                yield md, lineno, target, m


def cmd_summary() -> int:
    cats, strategies, mds = Counter(), Counter(), set()
    for md, _, target, _ in links():
        cat, strategy, _ = classify(target)
        cats[cat] += 1
        strategies[(cat, strategy)] += 1
        mds.add(md)
    print(f'OSS_SCREENSHOTS links={sum(cats.values())} md_files={len(mds)} ' +
          ' '.join(f'{k}={v}' for k, v in sorted(cats.items())))
    for (cat, strategy), n in sorted(strategies.items()):
        print(f'  {n:4d}  {cat:18s} {strategy}')
    return 0


def cmd_list(tsv: str | None) -> int:
    rows = ['md\tline\ttarget\tcategory\tstrategy\tdriver']
    for md, lineno, target, _ in links():
        rows.append('\t'.join([md, str(lineno), target, *classify(target)]))
    text = '\n'.join(rows) + '\n'
    if tsv:
        Path(tsv).parent.mkdir(parents=True, exist_ok=True)
        Path(tsv).write_text(text)
        print(f'wrote {len(rows) - 1} rows to {tsv}')
    else:
        sys.stdout.write(text)
    return 0


def cmd_apply() -> int:
    """Only the samples that still have an original link are copied and relinked (earlier ones are done)."""
    edits: dict[str, list] = {}
    for md, _, target, m in links():
        if target in SAMPLES:
            edits.setdefault(md, []).append((m.group(0), m.group(1), m.group(2), target))
    pending = {target for items in edits.values() for *_, target in items}
    missing = [SAMPLES[t][0] for t in pending if not (ROOT / 'ignored' / SAMPLES[t][0]).exists()]
    if missing:
        print('missing capture shots (run the capture drivers first):\n  ' + '\n  '.join(sorted(set(missing))))
        return 1
    (ROOT / DEST).mkdir(parents=True, exist_ok=True)
    for target in pending:
        shutil.copyfile(ROOT / 'ignored' / SAMPLES[target][0], ROOT / DEST / SAMPLES[target][1])
    rewritten = 0
    for md, items in edits.items():
        path = ROOT / md
        text = path.read_text()
        for whole, bang, label, target in items:
            rel = os.path.relpath(ROOT / DEST / SAMPLES[target][1], (ROOT / md).parent)
            archive_id = os.path.relpath(target, 'docs/evidence_packets')
            label = SAMPLES[target][2] if len(SAMPLES[target]) > 2 else label
            new = f'{bang}[{label}{REMAKE_LABEL}]({rel})（{ARCHIVE_NOTE}：`{archive_id}`）'
            if whole in text:
                text = text.replace(whole, new, 1)
                rewritten += 1
        path.write_text(text)
    print(f'OSS_SCREENSHOTS_APPLY shots={len({SAMPLES[t][1] for t in pending})} links={rewritten} files={len(edits)}')
    return 0


# Categories export-text turns into text. original-scene links not yet swapped for a remake capture (`apply`) go too:
# the public tree carries no original frame, and a later recapture simply moves the link to `remake`.
TEXTIFIED = ('original-measure', 'original-resource', 'original-scene')


def textify(md: str, text: str) -> tuple[str, int]:
    """`text` of repository-relative `md` with its original-measure / original-resource / original-scene links replaced by
    the link label and the archive id (fenced code untouched); -> (new text, replaced links)."""
    out, in_fence, replaced = [], False, 0
    for line in text.split('\n'):
        if FENCE.match(line):
            in_fence = not in_fence
        if not in_fence:
            def sub(m: re.Match) -> str:
                nonlocal replaced
                url = m.group(3).split('#')[0]
                if '://' in url or not url.lower().endswith(MEDIA):
                    return m.group(0)
                target = os.path.normpath(os.path.join(os.path.dirname(md), url))
                if classify(target)[0] not in TEXTIFIED:
                    return m.group(0)
                replaced += 1
                label = m.group(2).strip() or Path(target).name
                archive_id = os.path.relpath(target, 'docs/evidence_packets') if target.startswith('docs/evidence_packets/') else target
                return f'{label}（{ARCHIVE_NOTE}：`{archive_id}`）'
            line = LINK.sub(sub, line)
        out.append(line)
    return '\n'.join(out), replaced


def export_text(tree: Path) -> list[str]:
    """Apply textify to every .md under an exported tree; -> the changed paths (tree-relative)."""
    changed, links = [], 0
    for path in sorted(tree.rglob('*.md')):
        rel = path.relative_to(tree).as_posix()
        text = path.read_text(errors='ignore')
        new, replaced = textify(rel, text)
        if replaced:
            path.write_text(new)
            changed.append(rel)
            links += replaced
    print(f'OSS_SCREENSHOTS_EXPORT_TEXT links={links} files={len(changed)}')
    return changed


def main(argv: list[str]) -> int:
    cmd = argv[1] if len(argv) > 1 else 'summary'
    if cmd == 'summary':
        return cmd_summary()
    if cmd == 'list':
        tsv = argv[argv.index('--tsv') + 1] if '--tsv' in argv else None
        return cmd_list(tsv)
    if cmd == 'apply':
        return cmd_apply()
    if cmd == 'export-text' and len(argv) > 2:
        export_text(Path(argv[2]))
        return 0
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
