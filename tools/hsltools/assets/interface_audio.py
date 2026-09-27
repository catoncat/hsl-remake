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
from hsltools.sources.tables import digest, TABLES, blocks, parse_table

ROOT = Path('content/imported/hsl/shared/interface_audio')
NAMES = Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT')
HEADER = TABLES / 'resource.h'


def bindings():
    aliases = dict(re.findall(r'^#define\s+(sfx\w+)\s+(\d+)', HEADER.read_bytes().decode('cp950'), re.M))
    names = parse_table(NAMES.read_bytes())
    return {event: {'symbol': symbol, 'resource_id': int(aliases[symbol]), 'source_member': names[aliases[symbol]]}
            for event, symbol in [('confirm', 'sfxAccept'), ('take_up', 'sfxTakeUp'), ('put_down', 'sfxPutDown'), ('use_item', 'sfxUseItem'), ('game_over', 'sfxGameOver'), ('level_up', 'sfxLevelUp'), ('get_treasure', 'sfxGetTreasure'), ('sell_item', 'sfxSellItem'),
                                  ('cast_magic', 'sfxCastMagic'), ('hit_staff', 'sfxHitStaff'), ('hit_sword', 'sfxHitSword'),
                                  ('hit_bow', 'sfxHitBow'), ('hit_axe', 'sfxHitAxe'), ('hit_spear', 'sfxHitSpear'), ('hit_dagger', 'sfxHitDagger')]}


def weapon_hits():
    categories = {('itemIcon' + kind.title()): 'hit_' + kind for kind in ['staff', 'sword', 'bow', 'axe', 'spear', 'dagger']}
    # resource.h has no same-name claw impact alias. This explicit remake
    # binding uses the character's source attack sound once, without inventing
    # a second impact cue or silently pretending the claw is a sword.
    categories['itemIconClaw']=''
    categories['itemIconSting']='' # No native same-name impact alias; preserve the actor attack sound only.
    return {row['code']: categories[row['icon']] for row in blocks((TABLES / 'ITEM.TXT').read_bytes(), 'item')
            if row.get('type') == 'itemTypeWeapon' and row.get('icon') in categories}


def check():
    expected = bindings()
    sources = {path.as_posix(): digest(path.read_bytes()) for path in [HEADER, NAMES, TABLES / 'ITEM.TXT']}
    data = json.loads((ROOT / 'manifest.json').read_text())
    assert data['sources'] == sources and set(data['sounds']) == set(expected)
    assert data['weapon_hit_sounds'] == weapon_hits()
    for key, binding in expected.items():
        row = data['sounds'][key]
        assert all(row[field] == value for field, value in binding.items())
        raw = Path(row['res_path'].removeprefix('res://')).read_bytes()
        assert digest(raw) == row['sha256'] and profile(raw) == row['profile']
    print('INTERFACE_AUDIO_CHECK_PASS')


def build(pak):
    expected = bindings()
    sources = {path.as_posix(): digest(path.read_bytes()) for path in [HEADER, NAMES, TABLES / 'ITEM.TXT']}
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
              'weapon_binding_note': 'ITEM weapon icon category to same-named resource.h hit sound; claw has no same-named alias and explicitly uses character attack audio without a second hit cue. These are remake bindings, not a recovered complete native sound dispatch.',
              'limits': ['Modern playback timing and volume; no claim of complete original interface sound parity.']}
    (ROOT / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print('INTERFACE_AUDIO_IMPORT_PASS')


class InterfaceAudioTask(ScriptCheckTask):
    name = 'interface_audio'
    family = 'assets'
    inputs = (HEADER.as_posix(), NAMES.as_posix(), (TABLES / 'ITEM.TXT').as_posix())
    outputs = (ROOT.as_posix() + '/',)
    replaces = ('tools/hsl_interface_audio.py --check',)
    scripts = ('tools/hsltools/assets/interface_audio.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[InterfaceAudioTask]:
    return [InterfaceAudioTask()]
