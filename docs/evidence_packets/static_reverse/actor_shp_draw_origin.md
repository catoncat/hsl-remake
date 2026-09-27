# Actor SHP draw origin

> evidence: resource-derived; static-derived · status: live · functions: 0x45fa1e · updated: 2026-09-05

Checked: 2026-09-05. Evidence: resource-derived + static-derived.

EXE SHA-256: `f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7`.

Loader `0x45fa1e` validates TLHS and two-byte pixels. At `0x45fa5a`/`0x45fa5d` it reads header `+0x1c/+0x20` into the descriptor. At `0x45fa75` it retains X; `0x45fa7b`–`0x45fa80` negates Y. At `0x45faac` it subtracts X from each row segment X. `0x45fab1`–`0x45fab4` writes negative Y to the row descriptor; `0x45fb3f` increments Y per row. The decoded image top-left is object position minus this per-frame origin, not image center.

Reproduce:

```sh
r2 -e scr.color=0 -q -c 'pd 110 @ 0x45fa1e' "$HSL_ORIGINAL_DIR/hsl01.exe"
```

The importer now reads signed origins for all 150 live actor frames. ActorRuntime applies each origin on frame change. Leonard frame 001-00001 is 36×76 with origin (11,49); centering at (18,38) previously displaced its image by (-7,+11). The six facing-0 origins are (11,49), (10,49), (11,50), (12,51), (11,50), (10,50).

The loader copies pixel words unchanged when `0x4a421c == 0`; its alternate branch at `0x45fb07` converts 565 to 555 using `((pixel & 0xffc0) >> 1) | (pixel & 0x1f)`. This supports retaining source RGB565 decoding; later color processing remains unresolved.

Resource join: `obj-051.obs` object 6 names 雷歐納德, uses SHAPE\001-00001.SHP, defProcPlayerInstall, Data9=0. `global.obs` object 800 uses the same shape, Data6=SID_PLAYER0, Data7=1. Object 809 uses the separate upgraded 010 shape; replacing 001 with 010 is unsupported.

Still unresolved: costume color difference from runtime screenshots, direction mapping, pose cadence, complete roster/formation and grid-to-original coordinates. Correct image origins do not establish those contracts or visual parity. Header 0x10 semantics remain unresolved.
