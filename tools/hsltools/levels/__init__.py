"""Per-level data chain: one registry task family per tools/hsl_<family>.py --level N script.

  seed          battle_seed:N            the promoted original level (seed / terrain / map PNG)
  timeline      opening_timeline_compile:N, opening_timeline_check:N
  message_text  message_text_evidence_check:N
  map_objects   level_map_objects:N
  sounds        level_sounds:N
  source_texts  level_source_texts:N
  actors        level_actors:N (+ the shared encounter pool 500)
  story_scene   story_scene:N
  scenario      (no task) shared winfail readers of the assemblers
  battle        level_battle:N (the formal battle assembler)

Levels are enumerated from the repository data exactly as hsltools.legacy.check_commands
does (imported battleNNN directories, tracked content/battles files), never from a literal
list. The helpers below are shared by every family module.
"""
from __future__ import annotations

import contextlib
import json
from pathlib import Path
from typing import Any, Iterator

from hsltools.legacy import ENCOUNTER_RANGE, imported_levels
from hsltools.registry import CheckFailed, Context

# The chapter-wide shared evidence at content/imported/hsl/chapter01/ itself (opening_timeline.json
# compiled from the story051 script IR, message_text_evidence.json with the hand-listed chapter
# message ids): consumed by the development trial scenarios, checked by the argument-less legacy
# commands. Level 51 (the first battle) runs the ordinary per-level chain in battle051/.
CHAPTER_SHARED = 'chapter01'


def story_levels() -> list[int]:
    """Imported levels with a per-level actor / sound / text chain (every non-encounter level)."""
    return [level for level in imported_levels() if level not in ENCOUNTER_RANGE]


def actor_chain_levels() -> list[int]:
    """Story levels whose actors / story scene come from the per-level tools (every story level)."""
    return story_levels()


def encode_json(document: Any) -> bytes:
    """The tracked JSON form every per-level generator writes (indent 2, UTF-8, trailing newline)."""
    return (json.dumps(document, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def original_pak(ctx: Context) -> Path:
    """The original hsl.pak sits next to the documented EXE (WINEPREFIX drive_c/hsl by default)."""
    return ctx.original_exe.with_name('hsl.pak')


@contextlib.contextmanager
def legacy_failures(name: str) -> Iterator[None]:
    """The moved checkers report through SystemExit / ValueError / assert; the registry expects CheckFailed."""
    try:
        yield
    except (SystemExit, ValueError, AssertionError) as error:
        raise CheckFailed(f'{name}: {error!r}') from error
