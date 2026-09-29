"""Preserve every active ANIMAL action, using the original header's opcode schema.

This is an offline resource compiler, not a battle or animation runtime. Repeated
action lines append to the same program. No durations, implicit fallbacks or
unproven handler behavior are invented. --check works without Wine or the EXE.

Registry task animal_programs (family assets, GeneratedFilesTask): output
content/generated/hsl/animation/animal_programs.json, checked byte-for-byte. Bodies moved
verbatim from the former hsl_animal_programs.py. The task also owns the import of the
program source itself: `generate` copies PAK member data\\ANIMAL.TXT to
content/imported/hsl/chapter01/combat_animation/ANIMAL.TXT before compiling (combat_animation
reads that tracked copy and the compiled JSON, so the file-level dependency graph is acyclic);
`check` reads only the tracked files and pins ANIMAL.TXT through the JSON's source sha256.
"""
from __future__ import annotations

from collections import Counter
import hashlib
import json
from pathlib import Path
import re

from hsltools.registry import Context, GeneratedFilesTask, original_archive

ROOT = Path(__file__).resolve().parents[3]
SOURCES = {
    "programs": "content/imported/hsl/chapter01/combat_animation/ANIMAL.TXT",
    "opcodes": "content/imported/hsl/global/tables/ANIMAL.H",
    "actors": "content/imported/hsl/global/tables/SHAPEDEF.H",
}
MEMBERS = {"programs": "data\\ANIMAL.TXT", "opcodes": "data\\ANIMAL.H", "actors": "data\\SHAPEDEF.H"}
OUTPUT = ROOT / "content/generated/hsl/animation/animal_programs.json"
CHANNELS = {"action": ("shape", "number"), "m_action": ("m_shape", "m_number"),
            "s_action": ("s_shape", "s_number")}
FIELDS = {"code", "k_action", "fh_shape", *(x for pair in CHANNELS.values() for x in pair)}


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def uncomment(line: str) -> str:
    # The inspected grammar has no quoted strings; both comment forms occur.
    return re.split(r";|//", line, maxsplit=1)[0].strip()


def number(token: str) -> int:
    if not re.fullmatch(r"[+-]?(?:0[xX][0-9a-fA-F]+|[0-9]+)", token):
        raise ValueError(f"Not an integer literal: {token!r}")
    value = int(token, 16 if "x" in token.lower() else 10)
    if not -(1 << 31) <= value <= 0xFFFFFFFF:
        raise ValueError(f"Literal outside one 32-bit word: {token}")
    return value


def definitions(raw: bytes) -> dict:
    result = {}
    for line_number, line in enumerate(raw.decode("cp950").splitlines(), 1):
        active = uncomment(line)
        if not active:
            continue
        match = re.fullmatch(r"#define\s+(\w+)\s+(\S+)", active)
        if not match:
            raise ValueError(f"Header line {line_number}: unsupported definition {active!r}")
        name, token = match.groups()
        if name in result:
            raise ValueError(f"Header line {line_number}: duplicate {name}")
        comment = line.split("//", 1)[1] if "//" in line else ""
        result[name] = {"value": number(token), "parameters": re.findall(r"\[([^\]]+)\]", comment),
                        "source_line": line_number}
    return result


def parse_program(text: str, line_number: int, catalog: dict) -> list[dict]:
    tokens = [token.strip() for token in text.split(",")]
    if not tokens or any(not token for token in tokens):
        raise ValueError(f"Line {line_number}: empty action token")
    instructions, cursor = [], 0
    while cursor < len(tokens):
        name = tokens[cursor]
        if name not in catalog:
            raise ValueError(f"Line {line_number}: unknown opcode {name!r}")
        spec = catalog[name]
        count = len(spec["parameters"])
        args = tokens[cursor + 1:cursor + 1 + count]
        if len(args) != count:
            raise ValueError(f"Line {line_number}: {name} needs {count} arguments")
        try:
            values = [number(token) for token in args]
        except ValueError as error:
            raise ValueError(f"Line {line_number}, {name}: {error}") from error
        instructions.append({"op": name, "opcode": spec["value"], "args": values,
                             "arg_tokens": args, "source_line": line_number})
        cursor += 1 + count
    return instructions


def compile_sources(program_raw: bytes, opcode_raw: bytes, actor_raw: bytes) -> dict:
    header = definitions(opcode_raw)
    actors = definitions(actor_raw)
    catalog = {name: value for name, value in header.items() if not name.startswith("aniK")}
    if not catalog or any(not name.startswith("ani") for name in catalog):
        raise ValueError("Unsupported ANIMAL opcode header")
    if len({entry["value"] for entry in catalog.values()}) != len(catalog):
        raise ValueError("Duplicate numeric opcodes")
    includes, records, current = [], [], None
    for line_number, line in enumerate(program_raw.decode("cp950").splitlines(), 1):
        active = uncomment(line)
        if not active:
            continue
        if active.startswith("#INCLUDE"):
            include = active.split()
            if len(include) != 2 or include[1] not in ("ANIMAL.H", "SHAPEDEF.H") or current is not None:
                raise ValueError(f"Line {line_number}: unsupported include")
            includes.append(include[1])
            continue
        if active == "[animal]":
            current = {"section_line": line_number, "fields": {}, "programs": {}}
            records.append(current)
            continue
        match = re.fullmatch(r"(\w+)\s*=\s*(.+)", active)
        if current is None or not match:
            raise ValueError(f"Line {line_number}: unsupported ANIMAL grammar {active!r}")
        key, text = match.groups()
        if key in CHANNELS:
            current["programs"].setdefault(key, []).extend(parse_program(text, line_number, catalog))
        elif key in FIELDS:
            if key in current["fields"]:
                raise ValueError(f"Line {line_number}: duplicate field {key}")
            current["fields"][key] = {"token": text.strip(), "source_line": line_number}
        else:
            raise ValueError(f"Line {line_number}: unknown field {key}")
    if includes != ["ANIMAL.H", "SHAPEDEF.H"] or not records:
        raise ValueError("Missing source includes or animal records")
    seen, usage, channel_count = set(), Counter(), Counter()
    for record in records:
        fields = record["fields"]
        code = fields.get("code", {}).get("token")
        if code not in actors or not code.startswith("SID_"):
            raise ValueError(f"Unknown actor code {code!r}")
        sid = actors[code]["value"]
        if sid in seen:
            raise ValueError(f"Duplicate actor code {code}")
        seen.add(sid)
        record["code"], record["sid"] = code, sid
        for key, row in fields.items():
            if key.endswith("number"):
                row["value"] = number(row["token"])
            elif key in ("code", "k_action"):
                symbol = (actors if key == "code" else header).get(row["token"])
                if symbol is None:
                    raise ValueError(f"{code}: undefined {key} {row['token']}")
                row["value"] = symbol["value"]
        if "action" not in record["programs"]:
            raise ValueError(f"{code}: missing action")
        for channel, (shape_key, count_key) in CHANNELS.items():
            present = [shape_key in fields, count_key in fields, channel in record["programs"]]
            if any(present) and not all(present):
                raise ValueError(f"{code}: incomplete {channel} shape/count/program")
            if not all(present):
                continue
            frame_count = fields[count_key]["value"]
            if frame_count <= 0:
                raise ValueError(f"{code}: invalid frame count")
            channel_count[channel] += 1
            for instruction in record["programs"][channel]:
                usage[instruction["op"]] += 1
                if instruction["op"] == "aniSetShape" and not 0 <= instruction["args"][0] < frame_count:
                    raise ValueError(f"{code}: aniSetShape outside {channel} source frames")
    return {"schema": "hsl_animal_programs.v1", "evidence_tier": "resource-derived",
            "sources": {key: {"path": SOURCES[key], "member": MEMBERS[key], "sha256": digest(raw),
                              "pak_comparison": "crlf_to_lf" if key == "actors" else "exact_bytes"}
                        for key, raw in zip(SOURCES, (program_raw, opcode_raw, actor_raw))},
            "includes": includes, "opcode_definitions": catalog, "records": records,
            "summary": {"actors": len(records), "programs_by_channel": dict(sorted(channel_count.items())),
                        "instructions": sum(usage.values()), "opcode_usage": dict(sorted(usage.items()))},
            "limits": ["All active programs in this ANIMAL.TXT; no implicit m_action/s_action fallback.",
                       "Opcode numbers and argument labels come from ANIMAL.H, not dispatch-table order guesses.",
                       "No implicit aniOver appended; native parser termination is not proved by source parsing.",
                       "Raw counts are not seconds. Resource completeness does not prove handler or rendering parity.",
                       "No SHP pixels loaded and no battle state changed. Existing live manifest remains separate."]}


def build() -> dict:
    return compile_sources(*( (ROOT / path).read_bytes() for path in SOURCES.values()))


def check(path: Path = OUTPUT) -> dict:
    expected = build()
    actual = json.loads(path.read_text(encoding="utf-8"))
    if actual != expected:
        raise ValueError(f"ANIMAL program packet differs from complete source parsing: {path}")
    return expected


def original_member(pak: Path, key: str) -> bytes:
    """The bytes of MEMBERS[key] in the original archive (exactly one record must match).
    Existing canonical package decoding, never shell commands or Wine."""
    from hsltools.sources.pak import (find_decoded_paks_packages, find_paks_record_by_name,
                                      read_paks_record_bytes)
    member = MEMBERS[key]
    matches = [(p, r) for p in find_decoded_paks_packages(pak)
               if (r := find_paks_record_by_name(p["records"], "@:\\" + member))]
    if len(matches) != 1:
        raise ValueError(f"Missing or ambiguous original member: {member}")
    package, row = matches[0]
    return read_paks_record_bytes(package["path"], row,
                                  data_end_offset=int(package["paks"]["candidate_index_offset"]))


def check_pak(pak: Path) -> None:
    for key in MEMBERS:
        raw = original_member(pak, key)
        imported = (ROOT / SOURCES[key]).read_bytes()
        # This pre-existing SHAPEDEF import uses LF; the original uses CRLF.
        # Deliberately limited to this named source, not a general text fallback.
        if key == "actors":
            raw, imported = raw.replace(b"\r\n", b"\n"), imported.replace(b"\r\n", b"\n")
        if raw != imported:
            raise ValueError(f"Original source byte mismatch: {member}")


class AnimalProgramsTask(GeneratedFilesTask):
    name = 'animal_programs'
    family = 'assets'
    # ANIMAL.TXT is this task's own import (written by generate from the PAK), not an input
    # another task produces; ANIMAL.H / SHAPEDEF.H are the shared global table imports.
    inputs = (SOURCES["opcodes"], SOURCES["actors"])
    outputs = (OUTPUT.relative_to(ROOT).as_posix(), SOURCES["programs"])
    replaces = ('tools/hsl_animal_programs.py --check',)
    scripts = ('tools/hsltools/assets/animal_programs.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {self.outputs[0]: (json.dumps(build(), ensure_ascii=False, indent=2) + "\n").encode('utf-8')}

    def generate(self, ctx: Context) -> str:
        target = ctx.root / SOURCES["programs"]
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(original_member(original_archive(ctx), "programs"))
        return super().generate(ctx)

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        print("ANIMAL_PROGRAMS_CHECK_PASS" if mode == 'check' else "ANIMAL_PROGRAMS_BUILD_PASS")
        return json.dumps(json.loads(rendered[self.outputs[0]])["summary"], ensure_ascii=False)


def tasks() -> list[AnimalProgramsTask]:
    return [AnimalProgramsTask()]
