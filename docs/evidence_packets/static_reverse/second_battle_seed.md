# 第二战（level 52）M2 seed

> evidence: resource-derived · status: live · tools: hsltools/levels/seed.py · updated: 2026-09-10

Checked: 2026-09-10. Evidence tier is `resource-derived` unless a narrower
statement below says otherwise. This packet establishes the next battle's
inputs; it does **not** claim that battle 52 is playable in the remake yet.

## Reproducible inputs

`python3 tools/hsl.py generate battle_seed:52` reads exact named records from the user's
local original PAK in memory and promotes only compact facts plus decoded
product inputs. Raw PAK records remain outside tracked data. The tracked gate
does not require the original installation:

```sh
python3 tools/hsl.py check battle_seed:52
```

Tracked outputs:

- `content/generated/hsl/chapter01/battle052_seed.json`
- `content/generated/hsl/static/hsl01/level052_terrain.json`
- `content/imported/hsl/chapter01/battle052/level52.png`

The seed records source member names, byte lengths and SHA-256 digests for
`STORY052.TXT`, `winfail052.txt`, `level052.bin`, `level052.wrd`, `obj-052.h`,
`obj-052.obs`, and `shape01/level52.shp`.

## Map and spatial boundary

The decoded LEVEL52 SHP is 640×1280. The WRD is 20×40 (800 cells), with 23
cells carrying the statically recovered `0xff` blocking attribute. Dividing the
map dimensions by WRD dimensions yields 32×32 exactly. This is an independent
dimension-consistent candidate for reusing the existing 32-pixel grid contract;
it does not by itself prove native hit testing, movement cost or camera mapping.

The EVEF has 36 records, 35 non-zero. Joining its object-code field to
`obj-052.obs` gives 2 battle-manager records, 23 stand/map-object records,
9 records whose object process is `defProcEnemy`, and one `defProcPlayerInstall`
record. `defProcEnemy` is an object-process classification, **not** a faction
claim: the source names 023/024 this way even though the story explicitly walks
them alongside Leonard.

Notable source placement candidates include object 97 / `Enemy025` at
`(320,320)`, two object-98 / `Enemy026` records near `(384,384)` and `(256,384)`,
two object-94 / sprite-022 records near `(480,448)` and `(192,416)`, Leonard
(object 6) at `(320,1344)`, two 023 records at y=1408, and two 024 records at
y=1472. Several player-side actors therefore begin below the 1280px map extent;
STORY052 explicitly moves Leonard, two 023 actors and two 024 actors upward by
224 pixels. Their final gameplay cells and faction/control mapping remain a
scenario-adapter responsibility rather than an EVEF-only inference.

## Script boundary for the next rule adapter

STORY052 contains one win-status insert, one fail-status insert and two event
status inserts. Its active action stream also inserts eight objects through the
`obj_Story_Level52_Enemy21` symbol and contains nine `actWalkDispWait` actions.
The object header maps that insert symbol to object code 99 (`Enemy021`).

`winfail052.txt` has one `win`, one `fail`, and two `event` sections. The win
section checks `SID_ENEMY025`, then sets the next level/event pair to `58,58`;
the fail section checks `SID_PLAYER0`. Event 0 checks whether `SID_PLAYER0`
attacked `SID_ENEMY025` and then presents two message actions. Event 1 checks
`SID_ENEMY021` count `2` and has four active Enemy021 insert/walk pairs.

Those action names/order/arguments are source script structure. Handler timing,
exact condition polarity, object lifecycle details and any AI behavior not
spelled out by the script are not promoted from names alone.

## M2 implementation consequence

The shared PlayLoop no longer directly invokes first-battle script policy:
`BattleScenarioRuleAdapter` preserves the existing first-battle behavior and
dispatches every seed-backed battle to the data-driven `WinfailScenarioRules`
interpreter (the staged `SecondBattleScenarioRules` it first hosted was retired
on 2026-09-18). Pure tests map the tracked seed to Enemy025 / SID_PLAYER0 terminal
actors, `[58,58]`, the boss-engaged pair and Enemy021 threshold without treating
object process names as faction truth.

The second battle still cannot honestly be enabled by pointing the current scene
at a new JSON file. Resource/bootstrap and opening choreography remain first-
battle-shaped, and battle-52 actors/presentation assets are not complete. The
next slice is scenario-driven bootstrap/opening dispatch into the **same**
PlayLoop; it must not fork a second mutable battle implementation.
