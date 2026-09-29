"""Words a wrapped UI line must not split: every proper name the original tables name.

The player reported names torn across lines (城镇同伴条 緹／娜) and asked that paged dialogue
not cut words. Godot's ICU line breaker may break between any two CJK ideographs, so the
remake keeps a list of words that must stay on one line and breaks before such a word when
the shaped break would fall inside it (BattleUISkin.set_wrapped_text).

The words are resource-derived: the RESOURCE.TXT [name] strings that the original tables use
as names — PLAYERS name and job_show_name, ITEM, MAGIC and SPECIAL name ids — and the big-map
point names. The corpus scan records, per word, how many dialogue／narration lines (story
corpus actMessage／actShapeMessage texts and town te messages) contain it: that is the list
of lines where a break inside a name is possible, and the input of the Godot wrap check
(tests/run_ui_class_contract_tests.gd word_break_contracts).

Registry task protected_words (family data): output content/generated/hsl/text/protected_words.json.
"""
import json
import re
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import Context, GeneratedFilesTask
from hsltools.sources.tables import TABLES, blocks, override_rows, parse_table, table_rows

OUT = Path('content/generated/hsl/text/protected_words.json')
NAMES = Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT')
DEFINES = TABLES / 'resource.h'
WORLD_MAP = Path('content/imported/hsl/global/world_map/world_map.json')
STORY_SCRIPTS = Path('content/imported/hsl/story_corpus/scripts')
TOWN_MESSAGES = Path('content/imported/hsl/global/world_map/town_messages.json')
# A protected word is 2..8 characters of CJK text (names such as 琥 are one character and
# cannot be split; menu strings with spaces or punctuation are not names).
WORD = re.compile(r'^[\u3400-\u9fff\uf900-\ufaff·]{2,8}$')


def _defines() -> dict[str, int]:
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'#define\s+(\w+)\s+(\d+)', DEFINES.read_text(encoding='cp950'))}


def _resource_id(value: str, defines: dict[str, int]) -> int | None:
    value = value.strip()
    if value.isdigit():
        return int(value)
    return defines.get(value)


def corpus_lines() -> list[str]:
    lines = []
    for path in sorted(STORY_SCRIPTS.glob('STORY*.json')):
        for message in json.loads(path.read_text(encoding='utf-8'))['messages']:
            if message.get('text'):
                lines.append(str(message['text']))
    lines.extend(str(text) for text in json.loads(TOWN_MESSAGES.read_text(encoding='utf-8'))['messages'].values() if text)
    return lines


def build() -> dict:
    names = parse_table(NAMES.read_bytes())
    defines = _defines()
    sources: dict[str, set[str]] = {}

    def add(word: str, source: str) -> None:
        word = word.strip()
        if WORD.match(word):
            sources.setdefault(word, set()).add(source)

    for row in table_rows('PLAYERS.TXT'):
        for field in ('name', 'job_show_name'):
            rid = _resource_id(row.get(field, ''), defines)
            if rid is not None and str(rid) in names:
                add(names[str(rid)], 'PLAYERS.' + field)
    for table, section in (('ITEM.TXT', 'item'), ('MAGIC.TXT', 'magic'), ('SPECIAL.TXT', 'special')):
        for row in override_rows(table, blocks((TABLES / table).read_bytes(), section)):
            rid = _resource_id(row.get('name', ''), defines)
            if rid is not None and str(rid) in names:
                add(names[str(rid)], table.split('.')[0] + '.name')
    for point in json.loads(WORLD_MAP.read_text(encoding='utf-8'))['points']:
        add(str(point.get('name_text', '')), 'world_map.point')
    lines = corpus_lines()
    words = sorted(sources, key=lambda word: (-len(word), word))
    hits = {word: sum(1 for line in lines if word in line) for word in words}
    return {
        'schema': 'hsl_protected_words.v1',
        'evidence_tier': 'resource-derived',
        'claim': 'Proper names from the original tables that a wrapped UI line keeps on one line; the break rule itself is a remake choice (provisional: the original message renderer is not read).',
        'sources': [NAMES.as_posix(), (TABLES / 'PLAYERS.TXT').as_posix(), (TABLES / 'ITEM.TXT').as_posix(), (TABLES / 'MAGIC.TXT').as_posix(),
                    (TABLES / 'SPECIAL.TXT').as_posix(), DEFINES.as_posix(), WORLD_MAP.as_posix()],
        'corpus': {'story_scripts': STORY_SCRIPTS.as_posix(), 'town_messages': TOWN_MESSAGES.as_posix(), 'lines': len(lines),
                   'lines_with_protected_words': sum(1 for line in lines if any(word in line for word in words))},
        'words': [{'word': word, 'sources': sorted(sources[word]), 'corpus_lines': hits[word]} for word in words],
    }


class ProtectedWordsTask(GeneratedFilesTask):
    name = 'protected_words'
    family = 'data'
    inputs = (NAMES.as_posix(), 'content/imported/hsl/global/tables/', WORLD_MAP.as_posix(), STORY_SCRIPTS.as_posix() + '/', TOWN_MESSAGES.as_posix())
    outputs = (OUT.as_posix(),)
    scripts = ('tools/hsltools/data/protected_words.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        payload = json.loads(rendered[OUT.as_posix()])
        return f'PROTECTED_WORDS_PASS words={len(payload["words"])} corpus_lines={payload["corpus"]["lines"]} at_risk={payload["corpus"]["lines_with_protected_words"]}'


def tasks() -> list[ProtectedWordsTask]:
    return [ProtectedWordsTask()]
