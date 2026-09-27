"""Level dialogue from the original cp950 RESOURCE.TXT name table: the per-level speaker tables
(SPEAKER_IDS, from the level profiles' `speakers` sections), the message ids a level's tracked
seed scripts reference (seed_message_ids / level_message_ids), the importer that writes the
level's message_text_evidence.json next to its battle assets (import_dialogue; import_chapter_dialogue
refreshes the chapter-wide evidence at content/imported/hsl/chapter01/ that the development trials
load), and the checker that verifies the tracked evidence against the table
(message_text_evidence_check:N).

Registry task (tools/hsl.py check message_text_evidence_check:N): checks the level's tracked evidence;
`hsl generate message_text_evidence_check:N` runs import_dialogue (the level's evidence and its
section_title.png from the PAK and the level's battle seed, never reading the evidence it writes).
message_text_evidence_check:chapter01 (the chapter-wide evidence) stays a pure checker: its importer,
tools/hsl_chapter_dialogue.py --pak PAK --chapter, rewrites that file in place.
Importer bodies moved verbatim from that script (its ROOT is CHAPTER_ROOT here).
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from hsltools.legacy import imported_levels
from hsltools.levels import CHAPTER_SHARED, legacy_failures, profile
from hsltools.paths import ROOT
from hsltools.registry import Context, NoRegenerationPath, Task, original_archive
from hsltools.sources.tables import parse_table

DEFAULT_EVIDENCE = Path('content/imported/hsl/chapter01/message_text_evidence.json')

CHAPTER_ROOT = Path('content/imported/hsl/chapter01')
IDS = [0, 304, 305, 306, 307, *range(363, 378), 396, 397, 1101]
SEED_ROOT = Path('content/generated/hsl/chapter01')
SCHEMA = 'hsl_chapter01_imported_message_text_evidence.v1'
MESSAGE_ACTIONS = {'actMessage', 'actMessageIfExist', 'actSetDeadMessage', 'actShapeMessage'}
# actMessageIfExist,[player][serial],[true id],[false id],...: the false id is a message too (0 = none).
ALTERNATE_MESSAGE_ACTIONS = {'actMessageIfExist'}
_MESSAGE_ACTIONS_LOWER = {name.lower(): name for name in MESSAGE_ACTIONS}

# Speaker labels are resource text; which label a script token displays is a
# remake presentation choice unless the PLAYERS name field names the actor. The
# per-level tables are the `speakers` sections of content/battles/levels/NNN.json
# (hsltools.levels.profile, docs/architecture/LEVEL_PROFILES.md).
SPEAKER_IDS: dict[int, dict[str, str]] = {level: dict(table) for level, table in profile.section('speakers').items()}
# Random-encounter levels 501-578 (hsltools.legacy.ENCOUNTER_RANGE): their STORY
# only registers 雷歐納德's dead message 741 and their winfail speaks the shared win /
# fail lines (-1,121 narration and SID_雷歐納德,122), so every encounter shares one speaker
# table (the same EXTRAS.H slot-0 binding as level 3).
ENCOUNTER_SPEAKERS = {'SID_雷歐納德': '0'}
for _encounter_level in range(501, 579):
    SPEAKER_IDS.setdefault(_encounter_level, dict(ENCOUNTER_SPEAKERS))

# Why each token shows its label (resource-derived name field, or a provisional remake
# label); written into the level's message_text_evidence.json as speaker_name_policy.
SPEAKER_POLICY: dict[int, dict[str, str]] = profile.section('speaker_policy')


# The chapter-wide evidence speaks with the first battle's (level 51) speaker table.
CHAPTER_SPEAKER_LEVEL = 51


def chapter_paths() -> dict[str, Path]:
    return {'root': CHAPTER_ROOT, 'evidence': CHAPTER_ROOT / 'message_text_evidence.json', 'title': CHAPTER_ROOT / 'section_title.png', 'seed': None}


def level_paths(level: int) -> dict[str, Path]:
    code = f'{level:03d}'
    root = CHAPTER_ROOT / f'battle{code}'
    return {'root': root, 'evidence': root / 'message_text_evidence.json', 'title': root / 'section_title.png',
            'seed': SEED_ROOT / f'battle{code}_seed.json'}


def seed_message_ids(seed: dict) -> dict[str, list[str]]:
    """Message ids referenced by each script of a tracked battle seed, in source order."""
    result: dict[str, list[str]] = {}
    for script_key in ('story', 'winfail'):
        ids: list[str] = []
        if not isinstance(seed['scripts'].get(script_key), dict):
            continue
        for section in seed['scripts'][script_key]['sections']:
            for entry in section.get('messages', []):
                parts = str(entry).split(',')
                if len(parts) >= 2 and parts[1].strip().isdigit() and parts[1].strip() not in ids:
                    ids.append(parts[1].strip())
            for action in section.get('actions', []):
                for command in action.get('chain', []):
                    args = [str(arg) for arg in command.get('args', [])]
                    # Tokens match case-insensitively (WINFAIL002 spells actMEssage once).
                    name = _MESSAGE_ACTIONS_LOWER.get(str(command.get('name', '')).lower(), command.get('name'))
                    if name in MESSAGE_ACTIONS and len(args) >= 3 and args[2].isdigit() and args[2] not in ids:
                        ids.append(args[2])
                    if name in ALTERNATE_MESSAGE_ACTIONS and len(args) >= 4 and args[3].isdigit() and int(args[3]) > 0 and args[3] not in ids:
                        ids.append(args[3])
                    if str(command.get('name', '')) == 'actSelectInsertEvent' and len(args) >= 3 and args[2].isdigit():
                        # id, serial, num, (choice message id, event code) * num: the choice labels are messages.
                        for k in range(int(args[2])):
                            if len(args) > 3 + 2 * k and args[3 + 2 * k].isdigit() and args[3 + 2 * k] not in ids:
                                ids.append(args[3 + 2 * k])
        result[script_key] = ids
    return result


def level_message_ids(level: int, seed: dict) -> list[str]:
    ids = list(SPEAKER_IDS[level].values())
    for script_ids in seed_message_ids(seed).values():
        ids.extend(script_ids)
    return sorted(set(ids), key=int)


def _read_member(pak: Path, member: str) -> bytes:
    from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
    for package in find_decoded_paks_packages(pak):
        record = find_paks_record_by_name(package['records'], member)
        if record:
            return read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
    raise ValueError(f'{member} missing from PAK')


def _write_title(pak: Path, member: str, target: Path) -> dict:
    from hsltools.sources.shp import parse_shp, write_shp_preview
    title = _read_member(pak, member)
    target.parent.mkdir(parents=True, exist_ok=True)
    write_shp_preview(title, parse_shp(title), target)
    return {'source_member': member.replace('@:\\', '').upper(), 'res_path': 'res://' + target.as_posix(),
            'sha256': hashlib.sha256(title).hexdigest(), 'png_sha256': hashlib.sha256(target.read_bytes()).hexdigest()}


def import_chapter_dialogue(pak: Path) -> None:
    """Refresh the chapter-wide evidence (chapter_paths()) in place from the PAK RESOURCE.TXT."""
    paths = chapter_paths()
    data = _read_member(pak, '@:\\data\\resource.txt')
    messages = parse_table(data)
    source = CHAPTER_ROOT / 'source_texts/RESOURCE.TXT'
    source.write_bytes(data)
    path = paths['evidence']
    evidence = json.loads(path.read_text())
    for key in ('negative_evidence_checks', 'searched_payload_roots', 'searched_file_type_counts', 'negative_evidence', 'structured_text_table_candidates'):
        evidence.pop(key, None)
    evidence.update({
        'source_policy': 'Original RESOURCE.TXT name table; chapter dialogue decoded as cp950 with color controls removed and line breaks preserved.',
        'evidence_tier': 'resource-derived',
        'message_text_status': 'resolved_from_resource_table',
        'message_text_source_status': 'resource_txt_name_section',
        'source_member': '@:\\DATA\\RESOURCE.TXT',
        'source_sha256': hashlib.sha256(data).hexdigest(),
        'source_encoding': 'cp950',
        'messages': {str(i): messages[str(i)] for i in IDS},
        'speaker_names': {token: messages[rid] for token, rid in SPEAKER_IDS[CHAPTER_SPEAKER_LEVEL].items()},
        'unresolved_semantics': ['WORD*.SHP section title remains a visual resource, not a decoded text table'],
    })
    evidence['section_title'] = _write_title(pak, '@:\\shape01\\word051.shp', paths['title'])
    evidence['sources']['text_table'] = 'source_texts/RESOURCE.TXT'
    evidence['summary']['structured_text_table_candidate_count'] = 1
    path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')


def import_dialogue(pak: Path, level: int) -> None:
    paths = level_paths(level)
    data = _read_member(pak, '@:\\data\\resource.txt')
    messages = parse_table(data)
    tracked = (CHAPTER_ROOT / 'source_texts/RESOURCE.TXT').read_bytes()
    if hashlib.sha256(tracked).hexdigest() != hashlib.sha256(data).hexdigest():
        raise ValueError('PAK RESOURCE.TXT differs from the tracked chapter source text; re-import with --chapter first')
    seed = json.loads(paths['seed'].read_text())
    ids = level_message_ids(level, seed)
    code = f'{level:03d}'
    evidence = build_level_evidence(level, seed, messages, ids, hashlib.sha256(data).hexdigest())
    # The section title is shown by the STORY opening or, for a level whose battle
    # only starts from a chosen branch (STORY900 actSelectInsertEvent -> winfail event
    # 1), by the winfail chain the choice inserts. The member is the token's own
    # argument: the side-route variants 903 / 904 have no WORD903 / WORD904 and show
    # their base level's title (SHAPE01\WORD024.SHP / WORD019.SHP) instead.
    script_sections = list(seed['scripts']['story']['sections']) + list((seed['scripts'].get('winfail') or {}).get('sections', []))
    titles = [str(command['args'][0]) for section in script_sections for action in section.get('actions', [])
              for command in action.get('chain', []) if command.get('name') == 'actShowSectionName' and command.get('args')]
    if titles:
        evidence['section_title'] = _write_title(pak, '@:\\' + titles[0], paths['title'])
    else:
        evidence['section_title'] = None
    paths['evidence'].parent.mkdir(parents=True, exist_ok=True)
    paths['evidence'].write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')


def build_level_evidence(level: int, seed: dict, messages: dict[str, str], ids: list[str], source_sha256: str) -> dict:
    code = f'{level:03d}'
    per_script = seed_message_ids(seed)
    return {
        'schema': SCHEMA,
        'level': level,
        'source_policy': 'Original RESOURCE.TXT name table; level dialogue decoded as cp950 with color controls removed and line breaks preserved. Message ids come from the tracked battle seed scripts.',
        'evidence_tier': 'resource-derived',
        'sources': {
            'text_table': 'source_texts/RESOURCE.TXT',
            'text_table_root': CHAPTER_ROOT.as_posix(),
            'battle_seed': (SEED_ROOT / f'battle{code}_seed.json').as_posix(),
        },
        'message_text_status': 'resolved_from_resource_table',
        'message_text_source_status': 'resource_txt_name_section',
        'source_member': '@:\\DATA\\RESOURCE.TXT',
        'source_sha256': source_sha256,
        'source_encoding': 'cp950',
        'script_message_sources': [
            {'source_id': seed['sources'][key]['member'].split('\\')[-1], 'message_ids': per_script[key],
             'evidence_tier': 'resource_derived_script'}
            for key in ('story', 'winfail') if key in per_script
        ],
        'messages': {rid: messages[rid] for rid in ids},
        'speaker_names': {token: messages[rid] for token, rid in SPEAKER_IDS[level].items()},
        'speaker_name_policy': SPEAKER_POLICY.get(level, {}),
        'summary': {'message_id_count': len(ids), 'speaker_count': len(SPEAKER_IDS[level])},
        'unresolved_semantics': [
            'WORD*.SHP section title remains a visual resource, not a decoded text table',
            'message box layout, playback timing, portrait binding and handler blocking are not proven by the text table',
            'speaker labels for ??? actors are remake presentation choices, not original name reveals',
        ],
    }


def _safe_relative(value: str) -> Path:
    source = Path(value)
    if source.is_absolute() or '..' in source.parts:
        raise ValueError('text table must be a safe relative path')
    return source


def check_message_text_evidence(path: Path, level: int | None = None) -> dict:
    """level None: the chapter-wide evidence (content/imported/hsl/chapter01/message_text_evidence.json,
    hand-listed ids, no seed); otherwise the level's own evidence against its seed scripts."""
    evidence = json.loads(path.read_text())
    if evidence.get('message_text_status') != 'resolved_from_resource_table':
        raise ValueError('dialogue source is unresolved')
    source = _safe_relative(evidence['sources']['text_table'])
    root = path.parent
    if 'text_table_root' in evidence['sources']:
        root = _safe_relative(evidence['sources']['text_table_root'])
        if not root.as_posix().startswith('content/imported/hsl/'):
            raise ValueError('text table root must stay under content/imported/hsl')
    data = (root / source).read_bytes()
    if hashlib.sha256(data).hexdigest() != evidence['source_sha256']:
        raise ValueError('text table digest mismatch')
    table = parse_table(data)
    if level is None:
        ids = [str(i) for i in IDS]
    else:
        if int(evidence.get('level', 0)) != level:
            raise ValueError(f'evidence level differs from --level {level}')
        seed = json.loads(_safe_relative(evidence['sources']['battle_seed']).read_text())
        ids = level_message_ids(level, seed)
    if evidence['messages'] != {rid: table[rid] for rid in ids}:
        raise ValueError('dialogue differs from original table')
    expected_speakers = {token: table[rid] for token, rid in SPEAKER_IDS[CHAPTER_SPEAKER_LEVEL if level is None else level].items()}
    if evidence['speaker_names'] != expected_speakers:
        raise ValueError('speaker name differs from original table')
    title = evidence['section_title']
    title_path = (chapter_paths() if level is None else level_paths(level))['title']
    if title is None:
        if title_path.is_file():
            raise ValueError('section title image exists but the evidence records no actShowSectionName title')
        return {'level': level, 'message_id_count': len(evidence['messages'])}
    if title['res_path'] != 'res://' + title_path.as_posix():
        raise ValueError('section title res_path differs from the level layout')
    if hashlib.sha256(title_path.read_bytes()).hexdigest() != title['png_sha256']:
        raise ValueError('section title image differs from imported source')
    return {'level': level, 'message_id_count': len(evidence['messages'])}


def _repo_relative(path: Path) -> str:
    """level_paths() is cwd-relative (the tools run from the repository root)."""
    return (path.relative_to(ROOT) if path.is_absolute() else path).as_posix()


class MessageTextEvidenceCheckTask(Task):
    family = 'message_text_evidence_check'

    def __init__(self, level: int | None, evidence: Path | None = None) -> None:
        """level None: the chapter-wide evidence task message_text_evidence_check:chapter01."""
        self.level = level
        paths = chapter_paths() if level is None else level_paths(level)
        self.evidence = evidence or paths['evidence']
        self.name = f'message_text_evidence_check:{CHAPTER_SHARED if level is None else level}'
        title = _repo_relative(paths['title'])
        from hsltools.original_content import manifest
        has_title = level is not None and ((ROOT / title).is_file() or title in manifest())
        self.outputs = (_repo_relative(self.evidence),) + ((title,) if has_title else ())
        self.inputs = ((_repo_relative(self.evidence),) if level is None else ()) + ((_repo_relative(paths['seed']),) if paths['seed'] is not None else ()) \
            + profile.input_path(CHAPTER_SPEAKER_LEVEL if level is None else level) + ('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT',)
        self.replaces = () if evidence is not None else (
            ('tools/hsl_message_text_evidence_check.py',) if level is None
            else (f'tools/hsl_message_text_evidence_check.py --level {level}',))
        self.scripts = ('tools/hsltools/levels/message_text.py',)

    def check(self, ctx: Context) -> str:
        with legacy_failures(self.name):
            summary = check_message_text_evidence(self.evidence, self.level)
        return 'message text evidence ok: ' + str(summary)

    def generate(self, ctx: Context) -> str:
        if self.level is None:
            raise NoRegenerationPath(f'{self.name}: pure checker; the chapter evidence is refreshed in place by tools/hsl_chapter_dialogue.py --pak PAK --chapter')
        import_dialogue(original_archive(ctx), self.level)
        return self.check(ctx)


def tasks() -> list[MessageTextEvidenceCheckTask]:
    return [MessageTextEvidenceCheckTask(None), *(MessageTextEvidenceCheckTask(level) for level in imported_levels())]
