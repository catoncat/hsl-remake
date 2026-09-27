extends RefCounted
## Which finale follows STORY057's actSetNextPlayLevelGetOverEvent — the original's
## over-score dispatch (static-derived, hsl01.exe):
##   story interpreter 0x450840 case 0x81 (ACTION.H actSetNextPlayLevelGetOverEvent 129,
##   handler body 0x452a1a) calls 0x42c520, which reads the three over scores
##   (0x4c1bdc / 0x4c1be0 / 0x4c1be4 = gameoverID1..3, added by actAddOverScore /
##   teAddOverScore through 0x42c4d0) and the over flag (0x4c1bd8, OR-ed by
##   actSetOverFlag through 0x42c4b0), sorts the (id, score) pairs by score
##   descending with a bubble sort that swaps only on a strict "<" (ties keep the
##   id order 1, 2, 3), then walks the sorted ids:
##     id 1 → level 76 妖精王 when (flag & 3) == 0 — neither FreeEnemy nor EnemyJobUp set
##     id 2 → level 77 席德爾 when flag & gameoverflagFreeEnemy (TYPE.H 0x1)
##     id 3 → level 78 接觸   when flag & gameoverflagEnemyJobUp (TYPE.H 0x2)
##   the first id whose condition holds wins; when none does the result is 76.
## A developer switch (0x4c1ae8, set from the command line in main) lets keys 2/3/4
## force 76/77/78 in the original; that override is not part of the game and not
## modelled. The handler then sets next level/event to (level arg or result, result),
## so STORY057's "0" argument makes the pair [76, 76] / [77, 77] / [78, 78].
## Pure: the world state (hsl_world_state.v1 over_score / over_flag) in, a decision
## out; nothing here touches scene state.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ending_dispatch.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const SCHEMA := "hsl_ending_dispatch.v1"
const FLAG_FREE_ENEMY := 1
const FLAG_ENEMY_JOB_UP := 2
const FINALS := {1: 76, 2: 77, 3: 78}
const DEFAULT_FINAL := 76


## The finale level for a world state's over_score table ({"1": n, "2": n, "3": n},
## missing ids count 0) and over_flag bits.
static func route(over_score: Dictionary, over_flag: int) -> Dictionary:
	var pairs: Array = []
	for id in [1, 2, 3]:
		pairs.append([id, int(over_score.get(str(id), over_score.get(id, 0)))])
	# 0x42c520: up to three bubble passes over the two adjacent pairs, swapping when the
	# earlier score is strictly lower than the later one.
	for _pass in range(3):
		var swapped := false
		for index in range(2):
			if int(pairs[index][1]) < int(pairs[index + 1][1]):
				var held: Array = pairs[index]
				pairs[index] = pairs[index + 1]
				pairs[index + 1] = held
				swapped = true
		if not swapped:
			break
	var order: Array = []
	for pair in pairs:
		order.append(int(pair[0]))
	var chosen := 0
	var reason := "default"
	for pair in pairs:
		var id := int(pair[0])
		match id:
			1:
				if (over_flag & (FLAG_FREE_ENEMY | FLAG_ENEMY_JOB_UP)) == 0:
					chosen = id
			2:
				if (over_flag & FLAG_FREE_ENEMY) != 0:
					chosen = id
			3:
				if (over_flag & FLAG_ENEMY_JOB_UP) != 0:
					chosen = id
		if chosen != 0:
			reason = "over_score_id_%d" % id
			break
	return {
		"schema": SCHEMA,
		"level": int(FINALS[chosen]) if chosen != 0 else DEFAULT_FINAL,
		"over_score_id": chosen,
		"order": order,
		"scores": {"1": int(pairs_score(pairs, 1)), "2": int(pairs_score(pairs, 2)), "3": int(pairs_score(pairs, 3))},
		"over_flag": over_flag,
		"reason": reason,
	}


static func pairs_score(pairs: Array, id: int) -> int:
	for pair in pairs:
		if int(pair[0]) == id:
			return int(pair[1])
	return 0


## The next-level pair the handler writes for STORY057's "0" argument.
static func next_level_event(decision: Dictionary) -> Array:
	var level := int(decision.get("level", DEFAULT_FINAL))
	return [level, level]
