"""Check compact reward branch anchors; optional --exe verifies the original bytes.

These static anchors do not execute the full original reward/experience/UI state
machine. Source identity uses the project's existing SHA-locked PE reader.

Registry task reward_evidence (family evidence): the tracked packet is validated offline
exactly as the script's default (no --exe / --pak) run does; the original-byte comparisons
stay behind the script's flags. Bodies moved verbatim from the former hsl_reward_evidence.py (ROOT resolved
from this file's depth).
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from hsltools.native.image import EXE_SHA, image
from hsltools.registry import Context, ScriptCheckTask

ROOT = Path(__file__).resolve().parents[3]

PACKET = Path(__file__).resolve().parents[3] / "docs/evidence_packets/static_reverse/battle_reward_branches.json"
ANCHORS = [
    (0x407C76, "bf18000000", "carry starts with threshold 24"),
    (0x407C7F, "83f8ff740e", "minus-one skips the random draw"),
    (0x407C84, "6a65e8f50f0500", "carry random bound is 101"),
    (0x407C8E, "3bc77e15", "accept carry when sample <= threshold"),
    (0x407C95, "83ff0a7c0383ef06", "subtract six while threshold >= ten"),
    (0x407CAB, "e880f10200", "accepted carry goes through inventory insert"),
    (0x44F586, "e82576ffff", "drop exclusion predicate is checked first"),
    (0x44F5A8, "bb08000000", "scan eight inventory slots"),
    (0x44F5B0, "8db838010000", "drop stock is the current actor inventory at +0x138"),
    (0x44F5C5, "85c07517", "important items bypass random drop comparison"),
    (0x44F5CF, "6a648be8e8a8960000", "ordinary drop uses random bound 100"),
    (0x44F5DB, "403bc57d0b", "skip when sample + 1 >= get_ratio"),
    (0x44F5E0, "6a0156e8e8fcffff", "append one instance of the accepted code"),
]


def expected() -> dict:
    return {"schema": "hsl_reward_branches.v1", "evidence_tier": "static-derived", "exe_sha256": EXE_SHA,
            "anchors": [{"address": hex(address), "bytes": raw, "claim": claim} for address, raw, claim in ANCHORS],
            "limits": "Byte anchors, not full-function execution or a native probability distribution. Live draws carry and drops on the global stream (not saved; runtime-measured in battle_reward_inputs.md) and uses controlled-hostile kill eligibility, explicit claims, deferred loot and manual saves. Full original EXP/eligibility, pickup handler and tracked PLAYERS archive mismatch remain unresolved."}


def check(packet: dict, executable: Path | None = None) -> int:
    if packet != expected():
        raise ValueError("Reward evidence differs from the reviewed branch contract")
    if executable is not None:
        base, mapped = image(executable.read_bytes())
        for address, raw, _claim in ANCHORS:
            wanted = bytes.fromhex(raw)
            if mapped[address - base:address - base + len(wanted)] != wanted:
                raise ValueError(f"Reward instruction changed at {address:#x}")
    return len(ANCHORS)


class RewardEvidenceTask(ScriptCheckTask):
    name = 'reward_evidence'
    family = 'evidence'
    inputs = ()
    outputs = (PACKET.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_reward_evidence.py',)
    scripts = ('tools/hsltools/evidence/reward.py',)

    def verify(self, ctx: Context) -> None:
        packet = json.loads(PACKET.read_text(encoding="utf-8"))
        count = check(packet, None)
        print(f"REWARD_BRANCHES_PASS anchors={count} original_bytes_checked=False")


def tasks() -> list[RewardEvidenceTask]:
    return [RewardEvidenceTask()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--exe", type=Path)
    args = parser.parse_args()
    packet = expected() if args.write else json.loads(PACKET.read_text(encoding="utf-8"))
    count = check(packet, args.exe)
    if args.write:
        PACKET.write_text(json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"REWARD_BRANCHES_PASS anchors={count} original_bytes_checked={args.exe is not None}")


if __name__ == "__main__":
    raise SystemExit(main())
