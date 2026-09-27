"""Build the source skill coverage table used by the runtime skill contract.

The table intentionally includes every MAGIC.TXT and SPECIAL.TXT row. A source
row is only "ok" when it has an exact descriptor in initial_book.json and that
descriptor passes the same function/range policy gates as SkillResolutionRules;
source learning never silently grants an unregistered substitute.

Registry task skill_coverage (family skills): output content/generated/hsl/skills/coverage.json.
Bodies moved verbatim from the former hsl_skill_coverage.py.
"""
from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import TABLES, blocks, parse_table

OUT = Path("content/generated/hsl/skills/coverage.json")
BOOK = Path("content/generated/hsl/skills/initial_book.json")
LEARNING = Path("content/generated/hsl/roles/growth_lifecycle.json")
TARGETING = Path("content/generated/hsl/skills/targeting.json")
SOURCE_FILES = {"magic": "MAGIC.TXT", "special": "SPECIAL.TXT"}
# SupportMagicRules.accepted: any nonzero subset of Heal|HealMP|CureWeaken|CureParalysis|CurePoison|CureNoMagic.
SUPPORT_MASKS = [mask for mask in range(1, 0x10000) if mask & ~0xAE02 == 0]


def _skill_id(row: dict, channel: str) -> str:
    return f"{channel}:{row['type']}:{row['code']}"


def _function_mask(expression: object, symbols: dict) -> int | None:
    if not isinstance(expression, str) or not expression:
        return None
    mask = 0
    for token in expression.split(","):
        bit = symbols.get(token.strip())
        if not isinstance(bit, int) or bit <= 0 or bit > 0x7FFFFFFF:
            return None
        mask |= bit
    return mask


def _valid_pattern(pattern: object) -> bool:
    if not isinstance(pattern, dict) or not isinstance(pattern.get("size"), int):
        return False
    size = pattern["size"]
    rows = pattern.get("data")
    if pattern.get("shape") == "line":
        return 1 <= size <= 25 and isinstance(rows, list) and len(rows) == size and all(
            isinstance(row, list) and len(row) == 1 and isinstance(row[0], int) and 0 <= row[0] <= 127 for row in rows)
    if size < 1 or size > 25 or size % 2 == 0 or not isinstance(rows, list) or len(rows) != size:
        return False
    return all(isinstance(row, list) and len(row) == size and all(
        isinstance(value, int) and 0 <= value <= 127 for value in row) for row in rows)


def _descriptor_judgment(skill_id: str, row: dict, book: dict, targeting: dict) -> str:
    """Mirror descriptor_error's policy ordering, without importing Godot."""
    entry = book.get("skills", {}).get(skill_id)
    if not isinstance(entry, dict):
        return "unknown_skill"
    if entry.get("channel") != skill_id.split(":", 1)[0] or entry.get("type") != row.get("type") or entry.get("code") != row.get("code"):
        return "skill_identity_mismatch"
    if skill_id != f"{entry.get('channel')}:{entry.get('type')}:{entry.get('code')}" or not isinstance(entry.get("name"), str) or not entry["name"]:
        return "skill_identity_mismatch"
    fields = entry.get("fields")
    if not isinstance(fields, dict) or not isinstance(fields.get("damage"), str):
        return "invalid_skill_damage"
    bounds = fields["damage"].split(",")
    if len(bounds) != 2:
        return "invalid_skill_damage"
    try:
        low, high = (int(value.strip()) for value in bounds)
    except ValueError:
        return "invalid_skill_damage"
    if low < 0 or high < low or high == 2147483647:
        return "invalid_skill_damage"
    try:
        hit = int(fields.get("hit_ratio"))
    except (TypeError, ValueError):
        return "invalid_skill_hit_ratio"
    if hit < 0 or hit > 100:
        return "invalid_skill_hit_ratio"
    data = targeting
    mask = _function_mask(fields.get("function"), data.get("function_bits", {}))
    if mask is None:
        return "invalid_skill_function"
    if mask not in [1, 2, 4, 5, 8, 17, 0x20, 0x40, 0x400, 0x4000, 9, 0x60, 0x100, 0x1000, 0x1001, 0x101d, 0x2e00, 0x8000, 0x8002, 0x10000, 0x80000, 0x100001, 0x20001, 0x20000, 0x40000]:
        return "unsupported_skill_function"
    for key in ["range", "effect_range"]:
        name = fields.get(key)
        pattern = data.get("ranges", {}).get(name)
        if not isinstance(name, str) or pattern is None:
            return "missing_skill_range"
        if not _valid_pattern(pattern):
            return "invalid_skill_range"
    policy = entry.get("damage_policy", "")
    if policy == "native_special_sequence":
        return "ok"
    if policy == "native_special_poison":
        return "ok" if mask == 9 else "unsupported_skill_function"
    if policy == "native_magic_damage":
        return "ok" if mask == 1 else "unsupported_skill_function"
    if policy in ["native_magic_status", "native_magic_support", "native_magic_stat"]:
        accepted = [4, 5, 8, 17, 0x1000, 0x1001, 0x101d] if policy == "native_magic_status" else SUPPORT_MASKS
        if policy == "native_magic_stat":
            accepted = [0x20, 0x40, 0x100, 0x4000]
        return "ok" if mask in accepted else "unsupported_skill_formula"
    if policy == "native_special_utility":
        if entry.get("channel") != "special" or entry.get("damage_bounds") != "native_triangular":
            return "unsupported_skill_formula"
        try:
            scale = int(fields.get("attackpow_ratio"))
        except (TypeError, ValueError):
            return "invalid_special_power_ratio"
        if scale < 0 or scale > 1000:
            return "invalid_special_power_ratio"
        return "ok" if mask in [0x10000, 0x80000, 0x100001, 0x20001, 0x20000, 0x40000] else "unsupported_skill_function"
    if policy == "native_special_stat":
        if entry.get("channel") != "special" or entry.get("damage_bounds") != "native_triangular":
            return "unsupported_skill_formula"
        try:
            scale = int(fields.get("attackpow_ratio"))
        except (TypeError, ValueError):
            return "invalid_special_power_ratio"
        if scale < 0 or scale > 1000:
            return "invalid_special_power_ratio"
        return "ok" if mask in [0x20, 0x40, 0x60] else "unsupported_skill_formula"
    if policy == "native_special_support":
        if entry.get("channel") != "special" or entry.get("damage_bounds") != "native_triangular":
            return "unsupported_skill_formula"
        try:
            scale = int(fields.get("attackpow_ratio"))
        except (TypeError, ValueError):
            return "invalid_special_power_ratio"
        if scale < 0 or scale > 1000:
            return "invalid_special_power_ratio"
        return "ok" if mask in SUPPORT_MASKS else "unsupported_skill_formula"
    if policy == "native_special_status":
        if entry.get("channel") != "special" or entry.get("damage_bounds") != "native_triangular":
            return "unsupported_skill_formula"
        try:
            scale = int(fields.get("attackpow_ratio"))
        except (TypeError, ValueError):
            return "invalid_special_power_ratio"
        if scale < 0 or scale > 1000:
            return "invalid_special_power_ratio"
        return "ok" if mask in [4, 0x1000, 0x1001] else "unsupported_skill_function"
    if mask != 1:
        return "unsupported_skill_function"
    if policy == "native_special_damage":
        if entry.get("channel") != "special" or entry.get("damage_bounds") != "native_triangular":
            return "unsupported_skill_formula"
        try:
            scale = int(fields.get("attackpow_ratio"))
        except (TypeError, ValueError):
            return "invalid_special_power_ratio"
        return "ok" if 0 <= scale <= 1000 else "invalid_special_power_ratio"
    effect = data["ranges"][fields["effect_range"]]
    if effect["size"] != 1 or effect["data"][0][0] <= 0:
        return "unsupported_skill_effect_range"
    return "unsupported_skill_formula"


def _source_rows() -> dict[str, dict]:
    names = parse_table(Path("content/imported/hsl/chapter01/source_texts/RESOURCE.TXT").read_bytes())
    rows: dict[str, dict] = {}
    for channel, filename in SOURCE_FILES.items():
        for row in blocks((TABLES / filename).read_bytes(), channel):
            item = dict(row)
            item["skill_id"] = _skill_id(row, channel)
            item["channel"] = channel
            item["display_name"] = names.get(row.get("name"), row.get("name", ""))
            rows[item["skill_id"]] = item
    return rows


def build() -> dict:
    book = json.loads(BOOK.read_text())
    learning = json.loads(LEARNING.read_text())
    targeting = json.loads(TARGETING.read_text())
    sources = _source_rows()
    learners: dict[str, list[dict]] = {skill_id: [] for skill_id in sources}
    for job, definition in learning["jobs"].items():
        for row in definition.get("magic", []):
            if row["id"] in learners:
                learners[row["id"]].append({"job": job, "level": int(row["level"]), "kind": "magic"})
        for row in definition.get("special", []):
            if row["id"] in learners:
                learners[row["id"]].append({"job": job, "level": None, "tier": int(row["tier"]), "attributes": row["attributes"], "kind": "special"})
    initial_owners: dict[str, list[str]] = {skill_id: [] for skill_id in sources}
    for actor_id, actor in book.get("actors", {}).items():
        for skill_id in actor.get("supported_initial_ids", []):
            if skill_id in initial_owners:
                initial_owners[skill_id].append(actor_id)
    rows = []
    for skill_id, source in sources.items():
        rows.append({
            "id": skill_id,
            "channel": source["channel"],
            "type": source["type"],
            "code": source["code"],
            "display_name": source["display_name"],
            "fields": {key: value for key, value in source.items() if key not in {"skill_id", "channel", "display_name"}},
            "initial_owners": sorted(initial_owners[skill_id]),
            "learners": sorted(learners[skill_id], key=lambda item: (item["level"] is None, item["level"] or 0, item.get("tier", 0), item["job"])),
            "current_resolution": _descriptor_judgment(skill_id, source, book, targeting),
            "current_descriptor": book.get("skills", {}).get(skill_id),
        })
    rows.sort(key=lambda item: (item["channel"], item["type"], item["code"]))
    learned_order = sorted(
        (row for row in rows if row["learners"]),
        key=lambda row: (min(item["level"] for item in row["learners"] if item["level"] is not None) if any(item["level"] is not None for item in row["learners"]) else 999, row["id"]),
    )
    counts = Counter(row["current_resolution"] for row in rows)
    learned_counts = Counter(row["current_resolution"] for row in rows if row["learners"])
    return {
        "schema": "hsl_skill_coverage.v1",
        "evidence_tier": "resource-derived",
        "source_hashes": {filename: hashlib.sha256((TABLES / filename).read_bytes()).hexdigest() for filename in SOURCE_FILES.values()},
        "inputs": {"initial_book": BOOK.as_posix(), "learning": LEARNING.as_posix(), "targeting": TARGETING.as_posix()},
        "summary": {
            "total": len(rows),
            "supported": counts.get("ok", 0),
            "learned_total": sum(bool(row["learners"]) for row in rows),
            "learned_supported": sum(bool(row["learners"]) and row["current_resolution"] == "ok" for row in rows),
            "by_resolution": dict(sorted(counts.items())),
            "learned_by_resolution": dict(sorted(learned_counts.items())),
        },
        "skills": rows,
        "learned_order": [row["id"] for row in learned_order],
        "limits": [
            "Resolution is the current descriptor/range/function gate, not proof of original runtime equivalence.",
            "Special learning uses source tier and attribute gates; no level is invented for those rows.",
            "A source row absent from initial_book is reported as unknown_skill rather than mapped to another skill.",
        ],
    }


class SkillCoverageTask(GeneratedFilesTask):
    name = 'skill_coverage'
    family = 'skills'
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT',
              BOOK.as_posix(), LEARNING.as_posix(), TARGETING.as_posix())
    outputs = (OUT.as_posix(),)
    replaces = ('tools/hsl_skill_coverage.py --check',)
    scripts = ('tools/hsltools/data/skill_coverage.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        result = json.loads(rendered[OUT.as_posix()])
        return " ".join(["SKILL_COVERAGE_PASS", f"total={result['summary']['total']}", f"supported={result['summary']['supported']}", f"learned={result['summary']['learned_total']}", f"unsupported={result['summary']['by_resolution']}"])


def tasks() -> list[SkillCoverageTask]:
    return [SkillCoverageTask()]
