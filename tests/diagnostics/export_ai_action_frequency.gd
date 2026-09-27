extends "res://tests/diagnostics/export_enemy_turns.gd"

## AI action frequency, remake side (lane AIFREQ): many levels × AI seeds in one process, each
## run exactly the export_enemy_turns.gd run `_enemy_level.py batch` makes per (level, seed)
## (`--battle B --turns N --seed s --global-seed s --state FILE`: create with reward seed s,
## the global stream seeded(s), board overrides, every player waits, AI source seeded s), so
## the enemy_turn_v1 action rows are the ones the referee compares — here written one JSON
## object per run for hsltools.probes.ai_action_frequency to count by kind. Diagnostic only.
## `_prepare` is the referee's growth false (opening births with adjust_level [0, 0], lane
## LETHALITY); `--select 900=1` applies a level's opening menu event (--select-event) as the
## batch does (_enemy_level.MENU_EVENTS).
##
##   tools/godot.sh --headless --script res://tests/diagnostics/export_ai_action_frequency.gd -- \
##       --battles 051,res://content/battles/ohm_village.json --seeds 1-3 --turns 3 \
##       --state ignored/ai_action_frequency/board_growth_false.json --out FILE
##
## `--ai-seeds A-B` (instead of --seeds): the round-1 distribution the batch rule classifier reads
## (hsltools.probes._batch_rules): each level prepared once at seed 1 (reward／global seed 1), then
## one `_play` per AI source seed — AI seed 1 is the --seeds 1 run.
##
## Output FILE: one line per run {"battle", "seed", "error", "turns": [enemy_turn_v1 rounds,
## draws emptied]}; stdout prints AIFREQ_RUN per run and AIFREQ_DONE at the end.


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var opts := {"turns": 3, "seeds": "1-3", "battles": "", "state": "", "out": "", "select": "", "ai-seeds": ""}
	var i := 0
	while i + 1 < args.size():
		opts[str(args[i]).trim_prefix("--")] = str(args[i + 1])
		i += 2
	var seeds: Array = []
	var by_ai := not str(opts["ai-seeds"]).is_empty()
	for part in str(opts["ai-seeds"] if by_ai else opts["seeds"]).split(",", false):
		var span := part.split("-")
		for seed in range(int(span[0]), int(span[span.size() - 1]) + 1): seeds.append(seed)
	var file := FileAccess.open(str(opts["out"]), FileAccess.WRITE)
	if file == null or str(opts["battles"]).is_empty():
		printerr("AIFREQ usage: --battles A,B --seeds 1-3 --turns N --state FILE --out FILE")
		quit(2)
		return
	var selects := {}
	for pair in str(opts["select"]).split(",", false): selects[pair.get_slice("=", 0)] = int(pair.get_slice("=", 1))
	var runs := 0
	var failed := 0
	for battle in str(opts["battles"]).split(",", false):
		var shared := {}
		for seed in seeds:
			var run_opts := {"battle": battle, "turns": int(opts["turns"]), "seed": 1 if by_ai else seed, "global-seed": 1 if by_ai else seed}
			if by_ai: run_opts["ai-seed"] = seed
			if not str(opts["state"]).is_empty(): run_opts["state"] = str(opts["state"])
			if selects.has(battle): run_opts["select-event"] = selects[battle]
			if shared.is_empty() or not by_ai: shared = _prepare(run_opts)
			var prep := shared
			var run := _play(prep, run_opts, false)
			var turns: Array = []
			for turn in run["turns"]:
				var copy: Dictionary = turn.duplicate(true)
				copy.erase("rng")
				for action in copy["actions"]: action["draws"] = []
				turns.append(copy)
			var error := str(run["error"])
			runs += 1
			if not error.is_empty(): failed += 1
			file.store_line(JSON.stringify({"battle": battle, "seed": seed, "error": error, "turns": turns}))
			print("AIFREQ_RUN battle=%s seed=%d rounds=%d error=%s" % [battle, seed, turns.size(), error])
	file.close()
	print("AIFREQ_DONE runs=%d failed=%d" % [runs, failed])
	quit(0)
