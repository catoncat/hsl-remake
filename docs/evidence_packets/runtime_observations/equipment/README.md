# Equipment exchange: visible Control review

> evidence: runtime-measured · status: live · tools: capture_equipment_review.gd, run_inventory_equipment_tests.gd · updated: 2026-09-13

Observed 2026-09-13 with Godot 4.7.2. This is a controlled remake fixture, not a natural item acquisition or an original-game recording. Static evidence and unproved boundaries are in [original_inventory_equipment.md](../../static_reverse/original_inventory_equipment.md).

The fixture starts at the existing first-control entry, gives Leonard silver sword code 3 in `[241,3,241,246,0,0,0,0]`, and sets current HP to 17. Normal opening inventory remains `[241,241,241,246,0,0,0,0]`; no extra weapon or accessory is granted in the product. A later independent fixture uses accessory code 201 to exercise selection of the second accessory slot.

Mouse motion, press and release are delivered through `Viewport.push_input` to visible Control rectangles. The fixture does not invoke button signals, control the desktop pointer or treat a direct rule call as a UI click. The surrounding scene is paused to keep the inventory experiment bounded. Captures come from the 640×480 game viewport, not the desktop. CoreGraphics reported the built-in display at `(1600,251)` with size `1470×956`; the test window was explicitly positioned at `(1700,350)` and remained wholly on that display.

| Reviewed capture | Visible result |
| --- | --- |
| [weapon-preview.png](weapon-preview.png) | Silver sword preview: attack 54→59, defense 43→43, magic attack 17→22, speed 14→16. No live mutation before confirmation. |
| [weapon-confirmed-status.png](weapon-confirmed-status.png) | Current silver sword, attack 59, defense 43, magic attack 22, speed 16; wounded HP remains 17/30. |
| [inventory-after.png](inventory-after.png) | Replaced broad sword returned to the backpack. Equip-filtered list shows that weapon; the overall inventory still contains four occupied slots. The footer fits below the equipment frame. |
| [accessory-slot-choice.png](accessory-slot-choice.png) | Both accessory destinations and Cancel are visible inside the dialog. Mouse selection of slot 2 leaves slot 1 empty. |
| [full-backpack-refusal.png](full-backpack-refusal.png) | A full backpack cannot receive the removed helmet. The reason is visible and Confirm is disabled. |

The mouse route also cancels a weapon preview and verifies the entire loop state is unchanged, confirms the later swap, removes and re-equips the original helmet (defense 43→37→43), and verifies full-backpack rejection. [receipt.json](receipt.json) retains the final observed state and an empty failure list; [manifest.json](manifest.json) identifies the reviewed bytes.

During validation, a first synthetic click was intermittently not accepted when press/release were delivered across separate frames through the global input queue. That run correctly failed and was not promoted. The fixture now sends viewport-local motion/press/release in one ordered sequence. A footer touching the equipment frame and an undersized accessory-choice background were also corrected, then the final rendered route was rerun and visually inspected. Final result: `EQUIPMENT_RENDER_REVIEW_PASS`, exit 0, without script errors.

## Reproduce

Verify the current built-in display bounds before launching; coordinates below describe this machine's observed layout.

```sh
godot --path . --position 1700,350 --resolution 640x480 \
  --script res://tests/capture_equipment_review.gd
godot --headless --path . --script res://tests/run_inventory_equipment_tests.gd
```

The capture tool writes new raw results to `ignored/equipment-review/`. The headless suite separately checks missing-input atomic rejection, duplicate inventory selection, full-bag exchange, job/type/lock failure, terminal/dead/enemy rejection, stale callbacks, no cumulative stat drift, growth after equipment change and next-round speed rebuild. It compares dynamic refresh with all ten existing original growth fixtures both equipped and unequipped. These checks do not establish original held-item cancellation, action consumption, every passive equipment effect or other classes' formulas. Free equipment confirmation and atomic cancellation are the current documented remake policies.
