"""Original cp950 text tables: section blocks, RESOURCE name table, digests.

blocks() parses the INI-like tables (PLAYERS.TXT [character], ITEM.TXT [item],
MAGIC.TXT [magic], SPECIAL.TXT [special], *.obs [Object]); parse_table() reads the
[name] section of RESOURCE.TXT. Bodies moved verbatim from the former hsl_first_skill.py and
hsl_chapter_dialogue.py.

character_rows() is the one character table the role generators read: the PLAYERS.TXT
[character] rows followed by the authored rows of content/authored/roles/characters.json
(the same field vocabulary, written for the remake — a sequel's characters are added there,
PLAYERS.TXT stays the imported original and keeps its hash).

table_rows() is the one reader of the overridable original tables (OVERRIDABLE: PLAYERS.TXT,
ITEM.TXT) on the generator side: the imported rows with the authored overlay
content/authored/overrides/<PLAYERS|ITEM>.json laid over them (override_rows() does the same for a
reader that keeps its own row parser). The imported copy is never rewritten; the native parity
probes read it bare (blocks() / hsltools.native.sources.original_sources()). Without an overlay
file every row is returned unchanged.
"""
from __future__ import annotations

import hashlib
import json
import re

from hsltools.paths import ROOT, TABLES, RESOURCE_TXT

__all__ = ['TABLES', 'RESOURCE_TXT', 'AUTHORED_CHARACTERS', 'OVERRIDES', 'OVERRIDABLE', 'blocks', 'digest',
           'parse_table', 'resource_names', 'authored_characters', 'character_rows', 'table_overrides',
           'override_rows', 'table_rows']

AUTHORED_CHARACTERS = 'content/authored/roles/characters.json'
CHARACTERS_SCHEMA = 'hsl_authored_characters.v1'
# A character row needs what every consumer of a PLAYERS row reads without a default.
CHARACTER_REQUIRED = ('code', 'name_text', 'job', 'mode', 'str', 'dex', 'mind', 'con', 'move_point')

# Authored overlay over the imported original tables: <OVERRIDES>/<stem>.json per table,
# {"schema": OVERRIDE_SCHEMA, "rows": {"<code>": {"<field>": value}}}.
OVERRIDES = 'content/authored/overrides'
OVERRIDE_DIR = ROOT / OVERRIDES
OVERRIDE_SCHEMA = 'hsl_table_override.v1'
OVERRIDABLE = {'PLAYERS.TXT': 'character', 'ITEM.TXT': 'item'}


def blocks(raw, section):
    text = '\n'.join(line.split(';')[0] for line in raw.decode('cp950').splitlines())
    return [dict((k, v.strip()) for k, v in re.findall(r'^\s*(\w+)\s*=\s*(.+)$', b, re.M))
            for b in text.split('[' + section + ']')[1:]]


def _override_file(table: str) -> str:
    return f'{OVERRIDES}/{table.split(".")[0]}.json'


def table_overrides() -> dict[str, dict[str, tuple[str, dict[str, str]]]]:
    """{table: {code: (row key as written, {field: value})}} of every overlay file, validated
    for shape: a file per supported table, the schema, integer row keys (the table's `code`),
    non-empty field objects, string or integer values, `code` itself not overridable.
    {} when the folder does not exist."""
    if not OVERRIDE_DIR.is_dir():
        return {}
    supported = {_override_file(table).rsplit('/', 1)[1]: table for table in OVERRIDABLE}
    result = {}
    for path in sorted(OVERRIDE_DIR.iterdir()):
        if path.suffix != '.json':
            continue
        where = f'{OVERRIDES}/{path.name}'
        if path.name not in supported:
            raise ValueError(f'{where}: no overridable table {path.stem!r} (supported: {", ".join(sorted(supported))})')
        table = supported[path.name]
        data = json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(data, dict) or data.get('schema') != OVERRIDE_SCHEMA:
            raise ValueError(f'{where}: schema {data.get("schema") if isinstance(data, dict) else None!r} is not {OVERRIDE_SCHEMA}')
        rows = data.get('rows')
        if not isinstance(rows, dict):
            raise ValueError(f'{where}: rows must be an object of {{"<code>": {{"<field>": value}}}}')
        overlay: dict[str, tuple[str, dict[str, str]]] = {}
        for key, fields in rows.items():
            if not re.fullmatch(r'\d+', key):
                raise ValueError(f'{where}: rows["{key}"]: the row key is the {table} `code` (an integer)')
            if not isinstance(fields, dict) or not fields:
                raise ValueError(f'{where}: rows["{key}"] must be a non-empty object of {table} fields')
            values = {}
            for field, value in fields.items():
                if field == 'code':
                    raise ValueError(f'{where}: rows["{key}"].code: the row key cannot be overridden')
                if isinstance(value, bool) or not isinstance(value, (int, str)):
                    raise ValueError(f'{where}: rows["{key}"].{field}: value must be a string or an integer')
                values[field] = str(value)
            code = str(int(key))
            if code in overlay:
                raise ValueError(f'{where}: rows["{key}"]: row {code} is listed twice')
            overlay[code] = (key, values)
        result[table] = overlay
    return result


def override_rows(table: str, rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """The rows of `table` (parsed dicts with a `code`) with its overlay laid over them: new
    dicts for the overridden rows, the others as given. Every overlay row must be a `code` of
    the table and every field a column some row of the table has; otherwise ValueError naming
    the overlay file, row and field."""
    overlay = table_overrides().get(table)
    if not overlay:
        return rows
    where = _override_file(table)
    codes = [str(int(row['code'].strip())) if row.get('code', '').strip() else '' for row in rows]
    columns = {field for row in rows for field in row}
    for code, (key, fields) in overlay.items():
        if code not in codes:
            raise ValueError(f'{where}: rows["{key}"]: {table} has no row with code {code}')
        unknown = sorted(set(fields) - columns)
        if unknown:
            raise ValueError(f'{where}: rows["{key}"]: {table} has no field {", ".join(unknown)}')
    return [dict(row, **overlay[code][1]) if code in overlay else row for row, code in zip(rows, codes)]


def table_rows(table: str) -> list[dict[str, str]]:
    """The [section] rows of an overridable imported table (OVERRIDABLE) with its overlay."""
    return override_rows(table, blocks((TABLES / table).read_bytes(), OVERRIDABLE[table]))


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
    """PLAYERS.TXT [character] rows (with the overlay) followed by the authored characters."""
    return table_rows('PLAYERS.TXT') + authored_characters()


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
