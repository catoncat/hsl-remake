extends RefCounted
## The original's two window-slide steppers, one call per logic tick (OriginalTick), shared by
## every sliding window (battle panels, the shop's status window, the town's stone board).
## `approach` is 0x45e882(cur, target, speed) on the distance still to go: within 1 px it lands,
## else it steps min(speed, distance >> 3), at least 2. `retreat` is 0x45e80d(cur, start,
## tolerance, step) on the one moving axis, as distance travelled back towards the start point
## out of `span`: within `tolerance` of the start it lands, else it steps half the rest, at most
## `step`.
## provenance:
##   timing: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (0x45e882 slide in, 0x45e80d slide out)
##   timing: static-derived docs/evidence_packets/static_reverse/town_event_semantics.md
##     (town board 0x45e882 argument 40 in, 0x45e80d arguments 4／20 out)


## Distance still to go after one 0x45e882 tick (0 = landed).
static func approach(remaining: int, speed: int) -> int:
	if remaining <= 1:
		return 0
	return maxi(remaining - maxi(mini(speed, remaining >> 3), 2), 0)


## Distance travelled after one 0x45e80d tick (`span` = landed on the start point).
static func retreat(travelled: int, span: int, tolerance: int, step: int) -> int:
	var rest := span - travelled
	if rest <= tolerance:
		return span
	return travelled + mini(rest >> 1, step)
