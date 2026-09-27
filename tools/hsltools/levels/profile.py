"""Per-level knowledge files content/battles/levels/NNN.json (level_profile:N).

One file per level holds everything the tools and the sweep fixture know about that level
that is not derived from the imported sources: the formal battle profile (hsltools.levels.
battle), the story scene spec (hsltools.levels.story_scene), the presentation cast
(hsltools.levels.actors), the speaker table and its naming policy (hsltools.levels.message_text) and
the sweep fixture (tests/support/BattleForceWin.gd). Adding a level's knowledge is writing
this one file; the consumers read it through the accessors below and keep no per-level
dictionaries or branches of their own. Section layout: docs/architecture/LEVEL_PROFILES.md.

Registry task level_profile:N (tools/hsl.py check level_profile:N) is a pure checker: canonical
encoding, schema / level / section keys, cast rows and sweep fixture modes.
"""
from __future__ import annotations

import json
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.levels import encode_json
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context

SCHEMA = 'hsl_level_profile.v1'
DIRECTORY = ROOT / 'content/battles/levels'
SECTIONS = ('battle', 'story_scene', 'cast', 'speakers', 'speaker_policy', 'sweep_fixture', 'map_objects')
TOP_KEYS = ('schema', 'level', *SECTIONS, 'comments')
BATTLE_KEYS = ('id', 'title', 'initial_focus_unit_id', 'initial_objective_phase', 'role_overrides', 'initial_unit_state',
               'initial_status_overrides', 'result_labels', 'expected', 'footprint_radius_overrides', 'treasure_exclusions',
               'treasures', 'job_up_targets', 'derive_escape_zone', 'template_insert_skips', 'unit_ids',
               'unresolved_semantics')
BATTLE_REQUIRED = ('id', 'title', 'initial_focus_unit_id', 'initial_objective_phase', 'result_labels')
STORY_SCENE_KEYS = ('id', 'title', 'player_token', 'battle_opening_preview', 'player_installs',
                    'player_slot_inserts', 'standing_actor_inserts', 'token_overrides', 'static_bindings', 'shapeless_objects',
                    'excluded_source_actors',
                    'lead_unit_id', 'end_card', 'end_exit', 'end_routes', 'end_routes_evidence', 'map_alias_note', 'notes')
STORY_SCENE_REQUIRED = ('id', 'title', 'player_token')
MAP_ALIAS_NOTES = ('shape_of_its_own', 'no_shape', 'none')
CAST_KEYS = ('actors', 'speakers', 'shape_sets', 'shape_faces')
# tests/support/BattleForceWin.gd interprets these; a level without a fixture is force-won by `clear`.
SWEEP_MODES = ('clear', 'status', 'rounds', 'play_to_round', 'choice_branch')
MAP_OBJECT_LAYERS = ('foreground', 'back', 'backdrop')
SWEEP_KEYS = ('mode', 'opening_select_option', 'skip_opening', 'arm_win_statuses', 'advance_turn', 'players', 'arrive', 'turn',
              'event_statuses', 'win_statuses', 'run_hooks', 'expect_no_outcome', 'expect_win_status', 'expect_victory_resolved',
              'commit_outcome', 'finish', 'expect_handoff', 'rounds', 'clear_phases',
              'expect_win_unarmed_before', 'expect_undecided_after_rounds', 'expect_units', 'expect_install_unit', 'note')
SWEEP_FINISHES = ('result', 'pending_handoff', 'handoff_or_result')


def path(level: int) -> Path:
    return DIRECTORY / f'{level:03d}.json'


def levels() -> list[int]:
    """Every tracked profile, by level number (the file name is the level)."""
    return sorted(int(candidate.stem) for candidate in DIRECTORY.glob('[0-9][0-9][0-9].json'))


def load(level: int) -> dict:
    target = path(level)
    if not target.is_file():
        raise FileNotFoundError(f'level {level} has no profile at {target.relative_to(ROOT).as_posix()}')
    document = json.loads(target.read_text(encoding='utf-8'))
    if document.get('schema') != SCHEMA or int(document.get('level', -1)) != level:
        raise ValueError(f'{target.relative_to(ROOT).as_posix()}: schema {document.get("schema")!r} / level {document.get("level")!r} do not name level {level}')
    return document


def profiles() -> dict[int, dict]:
    return {level: load(level) for level in levels()}


def section(name: str) -> dict[int, dict]:
    """{level: section} for every profile that carries the section."""
    if name not in SECTIONS:
        raise KeyError(f'unknown level profile section {name!r}')
    return {level: document[name] for level, document in profiles().items() if name in document}


def casts() -> dict[int, dict]:
    """The cast section with its actor / speaker / shape-face rows as tuples (the manifests
    compare them with tuple(walk['actor_ids']))."""
    result = {}
    for level, cast in section('cast').items():
        row = dict(cast)
        row['actors'] = tuple(cast['actors'])
        row['speakers'] = tuple(cast['speakers'])
        if 'shape_faces' in cast:
            row['shape_faces'] = tuple(cast['shape_faces'])
        result[level] = row
    return result


def input_path(level: int) -> tuple[str, ...]:
    """The repository-relative profile path for a task's `inputs`, () when the level has none
    (the random encounters 5NN derive everything from their seed)."""
    target = path(level)
    return (target.relative_to(ROOT).as_posix(),) if target.is_file() else ()


def _expect_keys(where: str, document: dict, allowed: tuple[str, ...], required: tuple[str, ...] = ()) -> None:
    unknown = sorted(set(document) - set(allowed))
    missing = [key for key in required if key not in document]
    if unknown or missing:
        raise ValueError(f'{where}: unknown keys {unknown}, missing keys {missing}')


def _expect_actor_rows(where: str, rows: object) -> None:
    if not isinstance(rows, list) or any(not (isinstance(row, str) and len(row) == 3 and row.isdigit()) for row in rows):
        raise ValueError(f'{where}: expected a list of three-digit PLAYERS codes, got {rows!r}')
    if len(set(rows)) != len(rows):
        raise ValueError(f'{where}: duplicate rows in {rows!r}')


def validate(level: int) -> dict[str, int]:
    """Structural check of one profile: canonical bytes, top-level and section keys, cast rows,
    sweep fixture mode. Returns the section sizes for the PASS line."""
    target = path(level)
    raw = target.read_bytes()
    document = load(level)
    if encode_json(document) != raw:
        raise ValueError(f'{target.name}: not in canonical form (indent 2, key order kept, trailing newline); rewrite it with hsltools.levels.encode_json')
    _expect_keys(target.name, document, TOP_KEYS)
    if not set(document) & set(SECTIONS):
        raise ValueError(f'{target.name}: no section')
    if 'battle' in document:
        _expect_keys(f'{target.name} battle', document['battle'], BATTLE_KEYS, BATTLE_REQUIRED)
        expected = document['battle'].get('expected', {'units': 0, 'players': 0})
        if set(expected) != {'units', 'players'} or any(not isinstance(v, int) for v in expected.values()):
            raise ValueError(f'{target.name} battle.expected must be {{units, players}} integers: {expected!r}')
        unit_ids = document['battle'].get('unit_ids', {})
        if not isinstance(unit_ids, dict) or any(not (isinstance(k, str) and isinstance(v, str) and v) for k, v in unit_ids.items()):
            raise ValueError(f'{target.name} battle.unit_ids must map EVEF tokens / STORY insert symbols to id patterns: {unit_ids!r}')
    if 'story_scene' in document:
        _expect_keys(f'{target.name} story_scene', document['story_scene'], STORY_SCENE_KEYS, STORY_SCENE_REQUIRED)
        if document['story_scene'].get('map_alias_note', 'no_shape') not in MAP_ALIAS_NOTES:
            raise ValueError(f'{target.name} story_scene.map_alias_note must be one of {MAP_ALIAS_NOTES}')
        for row in document['story_scene'].get('excluded_source_actors', []):
            _expect_keys(f'{target.name} story_scene.excluded_source_actors', row, ('source_sid', 'source_actor_code', 'map_sprite_code', 'reason'),
                         ('source_sid', 'source_actor_code', 'reason'))
    if 'cast' in document:
        _expect_keys(f'{target.name} cast', document['cast'], CAST_KEYS, ('actors', 'speakers'))
        _expect_actor_rows(f'{target.name} cast.actors', document['cast']['actors'])
        _expect_actor_rows(f'{target.name} cast.speakers', document['cast']['speakers'])
        outside = sorted(set(document['cast']['speakers']) - set(document['cast']['actors']))
        if outside:
            raise ValueError(f'{target.name} cast.speakers outside cast.actors: {outside}')
    if 'speakers' in document:
        speakers = document['speakers']
        if not isinstance(speakers, dict) or any(not (isinstance(k, str) and isinstance(v, str) and v.isdigit()) for k, v in speakers.items()):
            raise ValueError(f'{target.name} speakers must map script tokens to RESOURCE.TXT ids: {speakers!r}')
    if 'speaker_policy' in document:
        # Policy rows are keyed by speaker token; narration (defNoOne) and action-name notes
        # (actShapeMessage, actSetPlayerName) are documentation rows without a speaker.
        outside = sorted(token for token in document['speaker_policy'] if token.startswith('SID_') and token not in document.get('speakers', {}))
        if outside:
            raise ValueError(f'{target.name} speaker_policy names tokens outside speakers: {outside}')
    if 'comments' in document:
        # The comment lines that documented the entries in the former Python dictionaries.
        _expect_keys(f'{target.name} comments', document['comments'], ('battle', 'story_scene', 'cast', 'speakers'))
    if 'map_objects' in document:
        # Per-record presentation overrides for the level's stand objects (hsltools.levels.map_objects):
        # layer_overrides {EVEF record_index: foreground|back|backdrop} where the generic obj field
        # reading (LAYER_HINTS) does not match the observed original draw order; evidence names why.
        _expect_keys(f'{target.name} map_objects', document['map_objects'], ('layer_overrides', 'evidence'), ('layer_overrides', 'evidence'))
        for record, layer in document['map_objects']['layer_overrides'].items():
            if not (isinstance(record, str) and record.isdigit()) or layer not in MAP_OBJECT_LAYERS:
                raise ValueError(f'{target.name} map_objects.layer_overrides: {record!r}: {layer!r} must map an EVEF record index to one of {MAP_OBJECT_LAYERS}')
    if 'sweep_fixture' in document:
        fixture = document['sweep_fixture']
        _expect_keys(f'{target.name} sweep_fixture', fixture, SWEEP_KEYS)
        if fixture.get('mode', 'clear') not in SWEEP_MODES:
            raise ValueError(f'{target.name} sweep_fixture.mode must be one of {SWEEP_MODES}: {fixture.get("mode")!r}')
        if fixture.get('finish', 'result') not in SWEEP_FINISHES:
            raise ValueError(f'{target.name} sweep_fixture.finish must be one of {SWEEP_FINISHES}: {fixture.get("finish")!r}')
        if (fixture.get('finish', 'result') != 'result') != ('expect_handoff' in fixture):
            raise ValueError(f'{target.name} sweep_fixture: a hand-off finish and expect_handoff go together')
    return {name: len(document[name]) for name in SECTIONS if name in document}


class LevelProfileTask(CheckTask):
    family = 'level_profile'
    replaces = ()  # born as a registry task: no historical command to replace

    def __init__(self, level: int) -> None:
        self.level = level
        self.name = f'level_profile:{level}'
        self.inputs = (path(level).relative_to(ROOT).as_posix(),)
        self.scripts = ('tools/hsltools/levels/profile.py',)

    def check(self, ctx: Context) -> str:
        try:
            sizes = validate(self.level)
        except (ValueError, FileNotFoundError, KeyError, TypeError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error
        return f'LEVEL_PROFILE_CHECK_PASS level={self.level} ' + ' '.join(f'{name}={size}' for name, size in sizes.items())


def tasks() -> list[LevelProfileTask]:
    return [LevelProfileTask(level) for level in levels()]
