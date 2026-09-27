# Important-item discard protection

> evidence: runtime-measured · status: live · tools: capture_equipment_review.gd, run_inventory_equipment_tests.gd · updated: 2026-09-13

Observed 2026-09-13, Godot 4.7.2. This is a bounded remake fixture using original ITEM code281 (通行證), a recovery item241 and antidote246. Normal opening inventory was not changed to grant the pass. Static original-source evidence is in [original_item_actions.md](../../static_reverse/original_item_actions.md).

The review uses visible Controls and viewport-local mouse motion/press/release events; it does not emit button signals or operate the desktop pointer. The 640×480 window was explicitly placed at `(1700,350)`, within the observed built-in display bounds `(1600,251,1470,956)`. Only the game viewport is captured.

| Capture | Observation |
| --- | --- |
| [important-item-protection.png](important-item-protection.png) | The important pass remains visible but disabled in Drop. The footer explains the restriction; ordinary recovery/antidote rows remain available. Clicking the pass leaves both the page and the entire battle state unchanged. |
| [ordinary-discard-confirmation.png](ordinary-discard-confirmation.png) | An ordinary item still opens confirmation. Mouse Cancel preserves all inventory and pending movement; reopening and confirming removes only the selected recovery item. |

[important-receipt.json](important-receipt.json) records an empty failure list, initial `[281,241,246,0,0,0,0,0]` and final `[281,246,0,0,0,0,0,0]`; [manifest.json](manifest.json) identifies the reviewed bytes. Actual result was `ITEM_RULES_RENDER_REVIEW_PASS`, exit0, without script errors. Final state confirms the pass was never discarded and the normal item path still commits its existing action policy.

```sh
godot --path . --position 1700,350 --resolution 640x480 \
  --script res://tests/capture_equipment_review.gd -- important
godot --headless --path . --script res://tests/run_inventory_equipment_tests.gd
```

Confirm the built-in display coordinates for the current environment before launching. Raw outputs go to `ignored/equipment-review/important-*` and `ordinary-discard-confirmation.png`. The targeted argument runs only the new item-rule review, not the previously accepted entire equipment route.

The headless suite also rejects direct/stale important-item callbacks, tests all five source-important items, checks missing metadata and verifies take_off is not mistaken for a discard restriction. Important items are not given a new transfer prohibition. Full original action-consumption parity remains unresolved and is not inferred from this UI review.
