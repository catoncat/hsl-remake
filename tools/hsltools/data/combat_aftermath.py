"""Join tracked death-message references to original text, without inventing rewards.

Registry task combat_aftermath_data (family actors): output
content/generated/hsl/combat/aftermath.json. Bodies moved verbatim from the former hsl_combat_aftermath_data.py.

Every PLAYERS [character] row gets a template: rows with a `dead_message` carry their
speaker and lines; rows without one carry `messages: []`, which BattleAftermath reads as
"this actor falls silently (fade only)". A defeated actor outside the table is therefore a
data error the runtime reports, not a row the original simply left mute.
"""
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import TABLES, blocks, digest, parse_table, character_rows

TEXT = Path("content/imported/hsl/chapter01/source_texts/RESOURCE.TXT")
RESOURCE_HEADER = Path("content/imported/hsl/global/tables/resource.h")
OUTPUT = Path("content/generated/hsl/combat/aftermath.json")


def speaker_id(row: dict[str, str]) -> str:
    """Monster / soldier rows name their speaker with `job_show_name`; party rows (001-009)
    only carry the resource.h `name_N` symbol of their own name (咕嚕 008 has a dead message).
    hsltools/levels/battle.py names a placed object's own death line (obj_Data8) with the same
    rule over the installed title."""
    if row.get("job_show_name"):
        return row["job_show_name"]
    symbol = row["name"].strip()
    for line in RESOURCE_HEADER.read_text(encoding="latin-1").splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "#define" and parts[1] == symbol:
            return parts[2]
    raise ValueError(f"actor {row['code']}: no speaker name for dead_message ({symbol})")


def build():
    players = (TABLES / "PLAYERS.TXT").read_bytes()
    resource = TEXT.read_bytes()
    messages = parse_table(resource)
    actors = {}
    for row in character_rows():
        code = row["code"].zfill(3)
        if code in actors:
            raise ValueError(f"duplicate actor {code}")
        ids = [value.strip() for value in row.get("dead_message", "").split(",") if value.strip() not in ("", "0")]
        # Leonard has no template death line; his script-owned terminal speech
        # remains with story presentation, so it requires no invented name join.
        speaker = speaker_id(row) if ids else ""
        actors[code] = {
            "speaker_id": speaker,
            "speaker": messages[speaker] if ids else "",
            "messages": [{"id": message_id, "text": messages[message_id]} for message_id in ids],
        }
    if not actors:
        raise ValueError("no PLAYERS character rows")
    return {
        "schema": "hsl_combat_aftermath.v1",
        "evidence_tier": "resource-derived",
        "sources": {"players_sha256": digest(players), "resource_sha256": digest(resource)},
        "actors": actors,
        "silent_actors": sorted(code for code, actor in actors.items() if not actor["messages"]),
        "limits": "Tracked PLAYERS references and RESOURCE text only. Every PLAYERS character row is listed; an empty messages list is the row's own silence (no dead_message), not a missing import. First listed nonzero line is a remake choice; original selection/timing, money and drops are not established. Leonard's terminal line remains owned by story presentation.",
    }


class CombatAftermathDataTask(GeneratedFilesTask):
    name = 'combat_aftermath_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/PLAYERS.TXT', TEXT.as_posix(), RESOURCE_HEADER.as_posix())
    outputs = (OUTPUT.as_posix(),)
    replaces = ('tools/hsl_combat_aftermath_data.py --check',)
    scripts = ('tools/hsltools/data/combat_aftermath.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'COMBAT_AFTERMATH_DATA_PASS'


def tasks() -> list[CombatAftermathDataTask]:
    return [CombatAftermathDataTask()]
