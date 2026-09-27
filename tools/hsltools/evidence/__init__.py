"""Evidence checkers: tracked evidence packets and manifests validated offline (family `evidence`).

Each module keeps its checker's bodies verbatim and adds a ScriptCheckTask whose `check`
prints the same result line the script printed; none needs the original install (the
*_evidence packets' optional original-byte comparisons stay behind each module's command
line: `PYTHONPATH=tools python3 -m hsltools.evidence.<module> --exe EXE [--pak PAK]`).
"""
