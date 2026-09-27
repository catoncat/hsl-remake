"""Original cp950 text tables: section blocks, RESOURCE name table, digests.

blocks() parses the INI-like tables (PLAYERS.TXT [character], ITEM.TXT [item],
MAGIC.TXT [magic], SPECIAL.TXT [special], *.obs [Object]); parse_table() reads the
[name] section of RESOURCE.TXT. Bodies moved verbatim from the former hsl_first_skill.py and
hsl_chapter_dialogue.py.

character_rows() is the one character table the role generators read: the PLAYERS.TXT
[character] rows followed by the authored rows of content/authored/roles/characters.json
(the same field vocabulary, written for the remake — a sequel's characters are added there,
PLAYERS.TXT stays the imported original and keeps its hash).
"""
from __future__ import annotations

import hashlib
import json
import re

from hsltools.paths import ROOT, TABLES, RESOURCE_TXT

__all__ = ['TABLES', 'RESOURCE_TXT', 'AUTHORED_CHARACTERS', 'blocks', 'digest', 'parse_table', 'resource_names',
           'authored_characters', 'character_rows']

AUTHORED_CHARACTERS = 'content/authored/roles/characters.json'
CHARACTERS_SCHEMA = 'hsl_authored_characters.v1'
# A character row needs what every consumer of a PLAYERS row reads without a default.
CHARACTER_REQUIRED = ('code', 'name_text', 'job', 'mode', 'str', 'dex', 'mind', 'con', 'move_point')


def blocks(raw, section):
    text = '\n'.join(line.split(';')[0] for line in raw.decode('cp950').splitlines())
    return [dict((k, v.strip()) for k, v in re.findall(r'^\s*(\w+)\s*=\s*(.+)$', b, re.M))
            for b in text.split('[' + section + ']')[1:]]


def authored_characters() -> list[dict[str, str]]:
    """The authored character rows (PLAYERS field names, values as the table strings; ints
    may be written as JSON numbers), validated: schema, required fields, distinct codes that
    no PLAYERS.TXT row uses. [] when the table does not exist."""
    path = ROOT / AUTHORED_CHARACTERS
    if not path.is_file():
        return []
    table = json.loads(path.read_text(encoding='utf-8'))
    if table.get('schema') != CHARACTERS_SCHEMA:
        raise ValueError(f'{AUTHORED_CHARACTERS}: schema {table.get("schema")!r} is not {CHARACTERS_SCHEMA}')
    original = {row['code'] for row in blocks((TABLES / 'PLAYERS.TXT').read_bytes(), 'character')}
    rows: list[dict[str, str]] = []
    seen: set[str] = set()
    for index, raw in enumerate(table.get('characters', [])):
        if not isinstance(raw, dict):
            raise ValueError(f'{AUTHORED_CHARACTERS}: characters[{index}] must be an object of PLAYERS fields')
        row = {str(key): str(value) for key, value in raw.items()}
        missing = [key for key in CHARACTER_REQUIRED if key not in row]
        if missing:
            raise ValueError(f'{AUTHORED_CHARACTERS}: characters[{index}] lacks {missing}')
        code = str(int(row['code']))
        if code in original or code in seen:
            raise ValueError(f'{AUTHORED_CHARACTERS}: code {code} is already a PLAYERS.TXT or authored row')
        seen.add(code)
        row['code'] = code
        row['evidence_tier'] = 'authored'
        rows.append(row)
    return rows


def character_rows() -> list[dict[str, str]]:
    """PLAYERS.TXT [character] rows followed by the authored characters."""
    return blocks((TABLES / 'PLAYERS.TXT').read_bytes(), 'character') + authored_characters()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def parse_table(data: bytes) -> dict[str, str]:
    messages = {}
    section = ''
    for line in data.decode('cp950').splitlines():
        line = line.strip()
        if line.startswith('['):
            section = line.lower()
        if section != '[name]':
            continue
        match = re.match(r'item\s*=\s*(\d+),(.*)', line, re.I)
        if match:
            key, body = match.groups()
            if key in messages:
                raise ValueError(f'duplicate resource id: {key}')
            messages[key] = re.sub(r'@[0-9]', '', body).replace('#', '\n')
    return messages


def resource_names() -> dict[str, str]:
    """The RESOURCE.TXT [name] table of the imported chapter (id -> text)."""
    return parse_table(RESOURCE_TXT.read_bytes())
