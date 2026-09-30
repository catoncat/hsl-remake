"""Extract explicit resource.h interface sound bindings from the original PAK.

Registry task interface_audio (family assets): output content/imported/hsl/shared/interface_audio/.
Bodies moved verbatim from the former hsl_interface_audio.py (its main() split into check() / build(pak)
statement-for-statement).
"""
import json
import re
import tempfile
from pathlib import Path

from hsltools.assets.actor_audio import profile
from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes, parse_xor_a8_wave_candidate, decoded_xor_a8_wave_bytes
from hsltools.sources.tables import digest, TABLES, override_rows, parse_table, table_rows

ROOT = Path('content/imported/hsl/shared/interface_audio')
NAMES = Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT')
HEADER = TABLES / 'resource.h'
PLAYERS = Path('content/imported/hsl/global/tables/PLAYERS.TXT')


def bindings():
    aliases = dict(re.findall(r'^#define\s+(sfx\w+)\s+(\d+)', HEADER.read_bytes().decode('cp950'), re.M))
    names = parse_table(NAMES.read_bytes())
    return {event: {'symbol': symbol, 'resource_id': int(aliases[symbol]), 'source_member': names[aliases[symbol]]}
            for event, symbol in [('confirm', 'sfxAccept'), ('take_up', 'sfxTakeUp'), ('put_down', 'sfxPutDown'), ('use_item', 'sfxUseItem'), ('game_over', 'sfxGameOver'), ('level_up', 'sfxLevelUp'), ('get_treasure', 'sfxGetTreasure'), ('sell_item', 'sfxSellItem'),
                                  ('cast_magic', 'sfxCastMagic'), ('hit_staff', 'sfxHitStaff'), ('hit_sword', 'sfxHitSword'),
                                  ('hit_bow', 'sfxHitBow'), ('hit_axe', 'sfxHitAxe'), ('hit_spear', 'sfxHitSpear'), ('hit_dagger', 'sfxHitDagger'),
                                  ('walk_water', 'sfxWalkWater'), ('walk_fire', 'sfxWalkFire')]}


def walk_water_rows():
    """PLAYERS.TXT rows with their own sound_walkwater (template +0x12, played by 0x409670 on 0x8000 cells
    instead of sfxWalkWater). Every such row repeats its sound_walk, so the remake reuses the walk sound."""
    rows = []
    for fields in override_rows('PLAYERS.TXT', [dict(re.findall(r'^\s*(\w+)\s*=\s*([^;\r\n]+?)\s*$', block, re.M))
                                                for block in PLAYERS.read_bytes().decode('cp950').split('[character]')[1:]]):
        if 'sound_walkwater' in fields:
            assert fields['sound_walkwater'] == fields.get('sound_walk'), fields.get('code')
            rows.append(str(int(fields['code'])))
    return sorted(rows, key=int)


# The impact switch's default branch: 0x404104 ja 0x404130 sends every icon above 5 to 405 sfxHitSword.
WEAPON_HIT_DEFAULT = 'hit_sword'


def weapon_hits():
    categories = {('itemIcon' + kind.title()): 'hit_' + kind for kind in ['staff', 'sword', 'bow', 'axe', 'spear', 'dagger']}
    # Table 0x404f6c covers icons 0..5 only (404..409); claw and sting (icons 6, 7) have no entry and take
    # the switch default WEAPON_HIT_DEFAULT.
    categories['itemIconClaw'] = ''
    categories['itemIconSting'] = ''
    return {row['code']: categories[row['icon']] for row in table_rows('ITEM.TXT')
            if row.get('type') == 'itemTypeWeapon' and row.get('icon') in categories}


def check():
    expected = bindings()
    sources = {path.as_posix(): digest(path.read_bytes()) for path in [HEADER, NAMES, TABLES / 'ITEM.TXT', PLAYERS]}
    data = json.loads((ROOT / 'manifest.json').read_text())
    assert data['sources'] == sources and set(data['sounds']) == set(expected)
    assert data['weapon_hit_sounds'] == weapon_hits() and data['weapon_hit_default'] == WEAPON_HIT_DEFAULT
    assert data['walk_water_is_walk_rows'] == walk_water_rows()
    for key, binding in expected.items():
        row = data['sounds'][key]
        assert all(row[field] == value for field, value in binding.items())
        raw = Path(row['res_path'].removeprefix('res://')).read_bytes()
        assert digest(raw) == row['sha256'] and profile(raw) == row['profile']
    print('INTERFACE_AUDIO_CHECK_PASS')


def build(pak):
    expected = bindings()
    sources = {path.as_posix(): digest(path.read_bytes()) for path in [HEADER, NAMES, TABLES / 'ITEM.TXT', PLAYERS]}
    ROOT.mkdir(parents=True, exist_ok=True)
    packages = find_decoded_paks_packages(pak)
    for key, row in expected.items():
        matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\' + row['source_member']))]
        if len(matches) != 1:
            raise ValueError('Missing or ambiguous sound: ' + row['source_member'])
        package, record = matches[0]
        raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / 'source.wav'
            source.write_bytes(raw)
            candidate = parse_xor_a8_wave_candidate(source, 0, len(raw))
            if candidate is None:
                raise ValueError('Unsupported sound format')
            audio = decoded_xor_a8_wave_bytes(source, candidate)
        target = ROOT / (key + '.wav')
        target.write_bytes(audio)
        row.update(source_sha256=digest(raw), sha256=digest(audio), profile=profile(audio), res_path='res://' + target.as_posix())
    result = {'schema': 'hsl_interface_audio.v1', 'evidence_tier': 'resource-derived', 'sources': sources, 'sounds': expected,
              'weapon_hit_sounds': weapon_hits(),
              'weapon_hit_default': WEAPON_HIT_DEFAULT,
              'walk_water_is_walk_rows': walk_water_rows(),
              'weapon_binding_note': 'ITEM weapon icon category to the resource.h hit sound the impact switch 0x404104 (table 0x404f6c) picks: icons 0..5 to 404..409; claw and sting (icons above 5) are empty here and take weapon_hit_default, the switch default 0x404130 (405 sfxHitSword). It is the third step of the ordinary hit chain, after the attacker sound_shoothit and the target sound_hit (actor_audio events shoothit／hit).',
              'limits': ['Modern playback timing and volume; no claim of complete original interface sound parity.']}
    (ROOT / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('INTERFACE_AUDIO_IMPORT_PASS')


class InterfaceAudioTask(ScriptCheckTask):
    name = 'interface_audio'
    family = 'assets'
    inputs = (HEADER.as_posix(), NAMES.as_posix(), (TABLES / 'ITEM.TXT').as_posix(), PLAYERS.as_posix())
    outputs = (ROOT.as_posix() + '/',)
    replaces = ('tools/hsl_interface_audio.py --check',)
    scripts = ('tools/hsltools/assets/interface_audio.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[InterfaceAudioTask]:
    return [InterfaceAudioTask()]
