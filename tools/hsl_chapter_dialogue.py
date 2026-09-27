#!/usr/bin/env python3
"""Import chapter dialogue from the original cp950 RESOURCE.TXT name table (hsltools.levels.message_text).

`--chapter` keeps the chapter-wide evidence at content/imported/hsl/chapter01/ (hand-listed
IDS, the level-51 speaker table; loaded by the development trial scenarios) updated in place.
`--level N` builds a fresh evidence file next to the level's battle assets; message ids are
collected from the tracked battle seed scripts instead of a hand-written list.
"""
import argparse
from pathlib import Path

from hsltools.levels.message_text import SPEAKER_IDS, import_chapter_dialogue, import_dialogue

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pak', type=Path, required=True)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument('--level', type=int, help='build the level\'s own evidence next to its battle assets')
    target.add_argument('--chapter', action='store_true', help='refresh the chapter-wide evidence at content/imported/hsl/chapter01/ in place')
    args = parser.parse_args()
    if args.chapter:
        import_chapter_dialogue(args.pak)
    else:
        if args.level not in SPEAKER_IDS:
            parser.error(f'no speaker profile for level {args.level}')
        import_dialogue(args.pak, args.level)
