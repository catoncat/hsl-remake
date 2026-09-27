"""Asset importers: original PAK / SHP / WAV members into content/imported (family `assets`).

Each module keeps its importer's bodies verbatim (bindings / build / check) and adds a
ScriptCheckTask: `check` runs the tracked-manifest validation the script's --check always
ran (no original install needed), `generate` runs build() against the original hsl.pak
next to the documented EXE (NotGeneratable, a generate failure, when it is not installed).
"""
