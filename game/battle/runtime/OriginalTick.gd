extends RefCounted
## The original's logic tick: one main-loop iteration = one object-process call = the
## unit of every aniDelay／actDelay／shape_delay／obj_Data7 count. Design period 16 ms
## (0x45f4b9: 1000 / 60 integer-divided, every caller passes 60) = 62.5 tick/s. On the
## user's Wine host the pacer measures 19.4 ms (GetTickCount granularity); the remake
## targets the design value (owner decision, lane R26), so a reference recording's seconds
## must be divided by 0.0194 to recover ticks before they are converted through here.
## Every presentation module expresses a tick-based duration through this file; a
## remake-invented beat that has no tick count stays in its own module, labelled so.
## provenance:
##   rules: n/a
##   layout: n/a
##   strings: n/a
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md; runtime-measured docs/evidence_packets/runtime_observations/original_tick_rate/README.md (period register 16; 19.4 ms host pacing explained by GetTickCount granularity)
##   audio: n/a

## 1000 / 60 with the original's unsigned integer division — 0.016, not 1/60.
const TICK_SECONDS := 0.016
const TICKS_PER_SECOND := 1.0 / TICK_SECONDS
## Reference recordings (original_gameplay_reference, the R24 memory samples) were taken
## on the 19.4 ms host; `ticks_from_host_seconds` folds such a measurement back to ticks.
const HOST_TICK_SECONDS := 0.0194


static func seconds(ticks: float) -> float:
	return ticks * TICK_SECONDS


static func ticks(seconds_value: float) -> float:
	return seconds_value / TICK_SECONDS


static func ticks_from_host_seconds(host_seconds: float) -> float:
	return host_seconds / HOST_TICK_SECONDS
