"""Promote one level's original script texts (STORY/winfail/obj header) next to its battle
assets (level_source_texts:N).

The tracked battle seed already records the PAK member names and SHA-256 digests
of these texts; this tool writes the raw cp950/ascii bytes so token order and
comments can be read without the original installation, and the check proves
the tracked copies still match the seed digests. Registry task (tools/hsl.py
check|generate level_source_texts:N); paths stay cwd-relative (the tools run from the
repository root).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from hsltools.levels import legacy_failures, original_pak, story_levels
from hsltools.paths import ORIGINAL_PAK
from hsltools.registry import Context, NotGeneratable, Task

DEFAULT_PAK = ORIGINAL_PAK
TEXT_KEYS = ('story', 'winfail', 'object_header', 'level_header')
README = """# Level {level} Source Texts

本目录保存从原版 PAK 提升出来的第 {level} 关原始脚本／头文件文本（`resource-derived` 输入层）。
文件字节与 `content/generated/hsl/chapter01/battle{code}_seed.json` 的 `sources` 摘要一致，
复跑：`python3 tools/hsl.py generate level_source_texts:{level}`（需原版 PAK）；核对：`python3 tools/hsl.py check level_source_texts:{level}`。

优先使用已结构化的 seed 与编译后的 `../opening_timeline.json`；需要查原始 token、注释或被注释掉的备用动作时再读这里。
原始脚本中的坐标、对象名或 message id 不是最终 Godot 行为；handler 语义、镜头、坐标投影和可见编舞仍需独立证据。
"""


def level_dir(level: int) -> Path:
    return Path(f'content/imported/hsl/chapter01/battle{level:03d}/source_texts')


def seed_path(level: int) -> Path:
    return Path(f'content/generated/hsl/chapter01/battle{level:03d}_seed.json')


def _member_basename(member: str) -> str:
    return member.split('\\')[-1]


def export(level: int, pak: Path) -> list[Path]:
    from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
    seed = json.loads(seed_path(level).read_text(encoding='utf-8'))
    target_dir = level_dir(level)
    target_dir.mkdir(parents=True, exist_ok=True)
    packages = find_decoded_paks_packages(pak)
    written: list[Path] = []
    for key in TEXT_KEYS:
        if key not in seed['sources']:
            continue  # story-only levels have no winfail script
        source = seed['sources'][key]
        member = str(source['member'])
        for package in packages:
            record = find_paks_record_by_name(package['records'], member)
            if record:
                data = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
                break
        else:
            raise ValueError(f'{member} missing from PAK')
        if hashlib.sha256(data).hexdigest() != source['sha256']:
            raise ValueError(f'{member} differs from the tracked seed digest; rebuild the seed first')
        target = target_dir / _member_basename(member)
        target.write_bytes(data)
        written.append(target)
    (target_dir / 'README.md').write_text(README.format(level=level, code=f'{level:03d}'), encoding='utf-8')
    return written


def check(level: int) -> dict[str, int]:
    seed = json.loads(seed_path(level).read_text(encoding='utf-8'))
    target_dir = level_dir(level)
    checked = 0
    for key in TEXT_KEYS:
        if key not in seed['sources']:
            continue
        source = seed['sources'][key]
        target = target_dir / _member_basename(str(source['member']))
        data = target.read_bytes()
        if len(data) != int(source['byte_length']) or hashlib.sha256(data).hexdigest() != source['sha256']:
            raise SystemExit(f'level source text differs from seed digest: {target}')
        checked += 1
    if not (target_dir / 'README.md').is_file():
        raise SystemExit(f'missing README in {target_dir}')
    return {'level': level, 'texts': checked}


class LevelSourceTextsTask(Task):
    family = 'level_source_texts'

    def __init__(self, level: int) -> None:
        self.level = level
        self.name = f'level_source_texts:{level}'
        self.outputs = (level_dir(level).as_posix() + '/',)
        self.inputs = (seed_path(level).as_posix(),)
        self.replaces = (f'tools/hsl_level_source_texts.py --level {level} --check',)
        self.scripts = ('tools/hsltools/levels/source_texts.py',)

    def check(self, ctx: Context) -> str:
        with legacy_failures(self.name):
            summary = check(self.level)
        return f"LEVEL_SOURCE_TEXTS_CHECK_PASS level={summary['level']} texts={summary['texts']}"

    def generate(self, ctx: Context) -> str:
        pak = original_pak(ctx)
        if not pak.is_file():
            raise NotGeneratable(f'{self.name}: original PAK not found at {pak}')
        written = export(self.level, pak)
        return f'LEVEL_SOURCE_TEXTS_EXPORT_PASS level={self.level} files={len(written)}'


def tasks() -> list[LevelSourceTextsTask]:
    return [LevelSourceTextsTask(level) for level in story_levels()]
