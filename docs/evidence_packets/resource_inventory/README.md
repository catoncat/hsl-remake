# Resource Inventory

> evidence: resource-derived · status: record-only · tools: hsl_resource_scanner.py · updated: 2026-09-27

`resource_manifest.json` is the canonical complete inventory of the scanned original packages. It supports targeted discovery and provenance checks; it is not a runtime asset catalog and is not loaded by Godot.

Use targeted search, for example:

```sh
rg -n 'LEVEL51|STORY051|BCMD01' docs/evidence_packets/resource_inventory/resource_manifest.json
```

Imported assets actually used by development live under `content/imported/hsl/`. Historical prose reports and duplicate manifest revisions were removed; the pre-cleanup Git bundle retains them if archaeology is ever required.
