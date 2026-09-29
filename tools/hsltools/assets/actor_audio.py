"""Import character-table audio bindings; playback timing is not inferred.

Registry task actor_audio (family assets): output content/imported/hsl/chapter01/actor_audio.json
and audio_normalized/. Bodies moved verbatim from the former hsl_actor_audio.py (its main() split into
check() / build(pak) statement-for-statement).
"""
import hashlib
import io
import json
import re
import tempfile
import wave
from pathlib import Path

from hsltools import original_content
from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.tables import override_rows
from hsltools.sources.pak import (find_decoded_paks_packages, find_paks_record_by_name,
    read_paks_record_bytes, parse_xor_a8_wave_candidate, decoded_xor_a8_wave_bytes)

SOURCE = Path('content/imported/hsl/global/tables/PLAYERS.TXT')
ROOT = Path('content/imported/hsl/chapter01')
OUTPUT = ROOT / 'actor_audio.json'
CODES = ('1', '21', '23', '24', '25', '26', '39', '2', '4', '6', '28', '36', '3', '61', '62')
EVENTS = ('walk', 'attack', 'miss', 'dead')


def bindings(raw):
    result = {}
    for fields in override_rows('PLAYERS.TXT', [{k: v.strip() for k, v in re.findall(r'^\s*(\w+)\s*=\s*([^;\r\n]+)', block, re.M)}
                                                for block in raw.decode('cp950').split('[character]')[1:]]):
        code = fields.get('code')
        if code in CODES:
            result[code] = {event: fields['sound_' + event].replace('\\', '/').lower() for event in EVENTS}
    if set(result) != set(CODES):
        raise ValueError('missing required character audio definitions')
    return result


def profile(data):
    with wave.open(io.BytesIO(data), 'rb') as sound:
        return {'channels': sound.getnchannels(), 'sample_rate': sound.getframerate(),
                'sample_width': sound.getsampwidth(), 'frame_count': sound.getnframes()}


def check():
    raw = SOURCE.read_bytes()
    characters = bindings(raw)
    expected = sorted({name for entry in characters.values() for name in entry.values()})
    manifest = json.loads(OUTPUT.read_text())
    assert manifest['source_sha256'] == hashlib.sha256(raw).hexdigest()
    assert manifest['characters'] == characters
    assert sorted(manifest['sounds']) == expected
    for item in manifest['sounds'].values():
        data = Path(item['path']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == item['sha256']
        assert profile(data) == item['profile']
    print('ACTOR_AUDIO_CHECK_PASS')


def normalized_destination(lower_name: str) -> Path:
    """audio_normalized/<name> spelled as the tracked file is (the original-derived manifest lists it, the public
    repository included), else as a file already on disk, else lower case. Other importers write this folder in
    PAK member case (Attack01.WAV), so without the manifest the spelling depended on which task ran first
    and a case-sensitive disk ended up with both spellings. A case-only variant on a case-insensitive disk is
    renamed to the tracked spelling."""
    folder = ROOT / 'audio_normalized'
    listed = sorted(name for name in original_content.manifest_files(folder.as_posix() + '/') if name.lower() == lower_name)
    folder.mkdir(parents=True, exist_ok=True)
    existing = [p for p in folder.iterdir() if p.name.lower() == lower_name]
    destination = folder / listed[0] if listed else existing[0] if existing else folder / lower_name
    for other in existing:
        if other.name != destination.name and destination.exists() and other.samefile(destination):
            staging = other.with_name(other.name + '.case')
            other.rename(staging)
            staging.rename(destination)
    return destination


def decode(packages, name):
    """(PAK record, raw payload, decoded WAV bytes) of the PAK member <name> (wav/...)."""
    member = '@:\\' + name.replace('/', '\\')
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], member)) is not None]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous audio member: ' + member)
    package, record = matches[0]
    payload = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / 'audio.wav'
        source.write_bytes(payload)
        candidate = parse_xor_a8_wave_candidate(source, 0, len(payload))
        if candidate is None:
            raise ValueError('unsupported audio format: ' + member)
        data = decoded_xor_a8_wave_bytes(source, candidate)
    return record, payload, data


def write_normalized(file_name, data):
    destination = normalized_destination(file_name)
    if destination.exists() and destination.read_bytes() != data:
        raise ValueError('existing normalized audio differs: ' + str(destination))
    destination.write_bytes(data)
    return destination


def build(pak):
    raw = SOURCE.read_bytes()
    characters = bindings(raw)
    expected = sorted({name for entry in characters.values() for name in entry.values()})
    packages = find_decoded_paks_packages(pak)
    sounds = {}
    for name in expected:
        record, payload, data = decode(packages, name)
        destination = write_normalized(Path(name).name, data)
        sounds[name] = {'source_member': record['name'], 'source_sha256': hashlib.sha256(payload).hexdigest(),
                        'path': destination.as_posix(), 'res_path': 'res://' + destination.as_posix(),
                        'sha256': hashlib.sha256(data).hexdigest(), 'profile': profile(data)}
    # audio_normalized/ also holds chapter-one sounds no character binds (the payload inspector imported
    # every wav the chapter references; the original-derived manifest lists them): decoded the same way so a
    # fresh checkout has them too. They are not character bindings, so actor_audio.json does not list them.
    bound = {Path(name).name.lower() for name in expected}
    for listed in sorted(original_content.manifest_files((ROOT / 'audio_normalized').as_posix() + '/')):
        if listed.lower() not in bound:
            write_normalized(listed.lower(), decode(packages, 'wav/' + listed)[2])
    manifest = {'schema': 'hsl_actor_audio.v1', 'evidence_tier': 'resource-derived',
                'source': SOURCE.as_posix(), 'source_sha256': hashlib.sha256(raw).hexdigest(),
                'characters': characters, 'sounds': sounds,
                'unresolved_semantics': ['character code is not automatically a scenario unit mapping',
                    'walk playback uses static-derived battle-step/scripted-frame cues; exact cadence, terrain alternatives, volume and mixing remain unresolved; attack/miss/dead now use remake combat-event timing']}
    OUTPUT.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print('ACTOR_AUDIO_IMPORT_PASS sounds=' + str(len(sounds)))


class ActorAudioTask(ScriptCheckTask):
    name = 'actor_audio'
    family = 'assets'
    inputs = (SOURCE.as_posix(),)
    outputs = (OUTPUT.as_posix(), (ROOT / 'audio_normalized').as_posix() + '/')
    replaces = ('tools/hsl_actor_audio.py --check',)
    scripts = ('tools/hsltools/assets/actor_audio.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[ActorAudioTask]:
    return [ActorAudioTask()]
