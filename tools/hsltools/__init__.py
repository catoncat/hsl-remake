"""hsltools: the shared core behind the tools/hsl_*.py scripts and the `hsl` task registry.

Shared core
  paths     repository, content and original-install locations (single source)
  sources   readers for the original text tables, PAKS archives, SHP graphics, level scripts /
            EVEF tables and WRD terrain
  native    EXE image loading, emulator machine factory, probe input tables and the ANIMAL
            dispatcher slice bounds
  model     the job stat model checked by the native probes
  typesafe  the TypeSafe System One client (function_catalog's judge)

Task packages (registry.TASK_PACKAGES; every module that defines tasks() is discovered)
  probes    bounded native probes: one evidence packet each (ProbeTask / PacketTask)
  levels    the per-level data chain (seed, timeline, message text, map objects, sounds,
            source texts, actors, story scenes, level 53 scenario) and the battle assembler
  data      table-derived JSON generators, authored trials, level scenarios and
            original-archive importers (GeneratedFilesTask / OriginalArchiveTask)
  checks    structural checkers over tracked data (CheckTask, no regeneration path)
  assets    asset importers (PAK / SHP / WAV -> content/imported) as ScriptCheckTask
  evidence  offline evidence-packet and manifest checkers (ScriptCheckTask / evidence_index)
  schema    the unit JSON Schema shared with game/sim/UnitSchema.gd

Registry
  registry  Task / GeneratedFilesTask / PacketTask / ScriptCheckTask, all_tasks(), affected()
  legacy    the command ledger: the check command each task `replaces`; all_tasks() fails
            unless every ledger command is replaced by exactly one task
  runner    the deterministic parallel job runner shared with tools/verify_runner.py

The package is the single definition: the former tools/hsl_*.py shims were deleted
(2026-09-21) and importers, tests and evidence headers name hsltools.<family>.<module>
directly. The remaining tools/hsl_*.py are stand-alone tools whose library bodies, where a
task module needs them, live in this package (the script imports the package, never the
reverse). tools/ must be on sys.path (it is whenever a tools script runs); the CLI is
tools/hsl.py, and a module whose command line has modes the registry lacks runs as
`PYTHONPATH=tools python3 -m hsltools.<family>.<module>`.
"""
