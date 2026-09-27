"""Shared shape of the native probe modules (hsltools.probes.*).

Each probe module keeps its bodies (fixtures / expected / execute / check ...) and exposes:

  execute_packet(exe) -> dict      run the bounded original instructions on the documented
                                   hsl01.exe (unicorn) and assemble the evidence packet
  summary_line(packet, executed_now) -> str   the PASS line

ProbeTask binds them to the registry (family 'probe'; `hsl check <name>` validates the tracked
packet, `hsl generate <name> [--exe EXE]` re-executes and rewrites it; `render=` picks the tracked
text, indent=2 by default, hsltools.data.compact_json_text for large receipts). run_probe is the
in-process equivalent used by the tests.
"""
from __future__ import annotations

from pathlib import Path
from typing import Callable

from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context, PacketTask

class ProbeTask(PacketTask):
    family = 'probe'
    # Every probe validates against the imported original tables (source hashes, fixtures).
    inputs = ('content/imported/hsl/global/tables/',)

    def __init__(self, name: str, packet: Path, validate: Callable[[dict], None],
                 execute_packet: Callable[[Path], dict], summary_line: Callable[[dict, bool], str],
                 replaces: tuple[str, ...] | None = None, render: Callable[[dict], str] | None = None) -> None:
        self.name = name
        self.packet = packet.relative_to(ROOT).as_posix()
        self.outputs = (self.packet,)
        # Probes migrated from tools/hsl_native_<name>_probe.py replace that ledger command;
        # probes added after the migration pass replaces=() (the ledger only records commands that existed).
        self.replaces = (f'tools/hsl_native_{name}_probe.py',) if replaces is None else replaces
        self.scripts = (f'tools/hsltools/probes/{name}.py',)
        self._validate, self._execute, self._summary = validate, execute_packet, summary_line
        self._render = render

    def validate(self, packet: dict) -> None:
        self._validate(packet)

    def execute(self, ctx: Context) -> dict:
        return self._execute(ctx.original_exe)

    def summary(self, packet: dict, executed_now: bool) -> str:
        return self._summary(packet, executed_now)

    def render_packet(self, packet: dict) -> str:
        return super().render_packet(packet) if self._render is None else self._render(packet) + '\n'


def run_probe(task: PacketTask, exe: Path | None, write: bool) -> str:
    """Offline check of the tracked packet (exe None), or re-execute on the given EXE
    (validate, optionally rewrite the packet) and return the PASS line."""
    if exe is None:
        if write:
            raise ValueError('--write requires original execution')
        try:
            return task.check(Context())
        except CheckFailed as error:
            raise ValueError(str(error)) from error
    ctx = Context(original_exe=exe)
    if write:
        return task.generate(ctx)
    packet = task.execute(ctx)
    task.validate(packet)
    return task.summary(packet, True)
