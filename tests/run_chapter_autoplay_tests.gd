extends SceneTree

## Chapter autoplay: the first chapter played end to end by machine. The walk is
## tests/support/StoryExplorer.gd (the story explorer's own map BFS, town exhaustion and scene
## playback) started at the campaign's start_level with no carry; every formal battle it is
## handed is really fought by tests/support/Autoplay.gd under the lookahead commander
## (tests/support/AutoplayBrain.gd; HSL_AUTOPLAY_BRAIN=scored|greedy picks another) — no fixture — and the party carries its growth (levels,
## points, equipment, job changes) through the product's own hand-offs. A lost battle is
## replayed from the same hand-off with the next loop seed, up to DEFAULT_TRIES attempts
## (HSL_CHAPTER_TRIES overrides it); retry k of a hand-off that carries the damage stream also
## boots with a fresh one (_reseed_retry_damage), so a replay is not the same hits and damage.
## HSL_CHAPTER_START=ohm_village starts where the explorer does instead
## (the big map after 歐姆村 with a fresh party), skipping the prologue chain 51 → 52 → 53 → 1.
## Every shop the walk opens is shopped (tests/support/AutoplayShopping.gd: best gear per member
## and slot, worn at once, restocking up to 4 healing items each before any gear; HSL_AUTOPLAY_GOLD=unlimited makes purchases
## free) and recorded per town in `towns`. A won battle whose pending loot the hand-off cannot carry
## (a separate party: level 53) is settled like a player leaving the result page — take what fits,
## 放棄 the rest — printed as `CHAPTER_AUTOPLAY_LOOT level=…` and kept in the battle row's
## `loot_settled`. HSL_CHAPTER_BUDGET_SECONDS=N bounds the run: past N seconds no further battle is started (the
## commander also stops simulating), the run ends with `budget_exhausted` naming the battle it did
## not start and still passes. Unset, a standalone run gets the deep gate's DEFAULT_BUDGET_SECONDS
## (tools/verify_runner.py CHAPTER_BUDGET_SECONDS); HSL_CHAPTER_BUDGET_SECONDS=0 lifts the bound.
## One `CHAPTER_AUTOPLAY level=… outcome=… tries=…` line per battle, a
## `CHAPTER_AUTOPLAY_PASS game_clear=true|false stuck_at=… budget_exhausted_at=…` summary, and the run written to
## content/generated/hsl/development/autoplay/chapter.json (guarded by `hsl check
## autoplay_chapter`; no wall clock inside, so a deterministic walk rewrites it byte-identically —
## the loop seeds are fixed and the global RNG — the big map's encounter dice (WorldMapRules) and
## the towns' random events (TownEventRules) — is seeded from BASE_SEED before the walk starts, so
## one tree always meets the same encounters). The pass bar is a complete report: GameClear, or the first battle the
## commander could not win with its attempts and outcome recorded — that battle's cause
## (rules defect / balance / driver) is the report's, not this suite's, to classify. The run
## fails only on a defect: an attempt that ends in a dead_end (unless the sweep's
## known_dead_ends.json lists its level), a walk that ends by exhaustion, or a SCRIPT ERROR
## (tools/godot.sh). The rewritten chapter.json is not compared with the tracked file — the
## deep gate's wall-clock budget makes it unrepeatable under load — and stays in the worktree;
## its headline (game_clear, stuck_at, budget_exhausted_at, battles fought／won, retries) is
## printed against the tracked file's as one `CHAPTER_AUTOPLAY_DRIFT fields=[…]` line with a
## `<field>: old -> new` line per change, and the PASS line ends `drift=<fields>|none`. Nothing
## here is evidence about original balance. Runs in the deep gate (tools/verify.sh --deep):
## `tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_chapter_autoplay_tests.gd`.

const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const Runtime = preload("res://game/battle/scene/BattleSceneRuntime.gd")
const Autoplay = preload("res://tests/support/Autoplay.gd")
const Brain = preload("res://tests/support/AutoplayBrain.gd")
const StoryExplorer = preload("res://tests/support/StoryExplorer.gd")
const Shopping = preload("res://tests/support/AutoplayShopping.gd")
const PartyEquipment = preload("res://game/sim/PartyEquipmentRules.gd")
const CarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")
const RegenDiff = preload("res://tests/support/RegenDiff.gd")

const CHAPTER_PATH := "res://content/generated/hsl/development/autoplay/chapter.json"
## The sweep's register of battles whose dead_end is recorded but not yet fixed.
const KNOWN_DEAD_ENDS_PATH := "res://content/generated/hsl/development/autoplay/known_dead_ends.json"
const SCHEMA := "hsl_autoplay_chapter.v1"
## Attempts per battle before the chapter is declared stuck there (HSL_CHAPTER_TRIES overrides):
## a player replays a lost battle. Every row records its tries, so a regression shows as more
## retries before it shows as a new stuck_at. The 2026-09-21 ablation (3 attempts stuck at the
## same battle as 1) no longer holds: on the B2b tree 53 and 5 each needed a second attempt.
const DEFAULT_TRIES := 3
## Loop seed of a battle's first attempt; attempt n uses BASE_SEED + n.
const BASE_SEED := 1
const START_CAMPAIGN := "campaign"
const DEFAULT_BRAIN := Brain.MODE_LOOKAHEAD
const START_OHM_VILLAGE := "ohm_village"
## The battle the explorer's fresh-party start follows (歐姆村, campaign key 1): its roster is
## the party the walk carries, so its scenario seeds the carry's member records.
const FRESH_PARTY_TEMPLATE_LEVEL := "1"
const HANDOFF_DIR_ENV := "HSL_CHAPTER_HANDOFF_DIR"
const EVENT_COMPLETION_BATTLES := ["res://content/battles/battle_073.json", "res://content/battles/battle_078.json"]

var failures: Array[String] = []
var campaign: Dictionary = {}
var tries_limit := DEFAULT_TRIES
var start := START_CAMPAIGN
## One row per battle in play order: {level, scenario, outcome, tries, party, attempts}.
var battles: Array = []
## Attempts of the battle currently being replayed, keyed by scenario path.
var attempts_by_scenario: Dictionary = {}
var stuck_at: Dictionary = {}
var brain_mode := DEFAULT_BRAIN
## Budget of a run without HSL_CHAPTER_BUDGET_SECONDS: the deep gate's (tools/verify_runner.py
## CHAPTER_BUDGET_SECONDS), so a standalone run is bounded the way the gate's is.
const DEFAULT_BUDGET_SECONDS := 600
## Wall-clock budget in seconds (0 = none) and the battle the run stopped before because of it.
var budget_seconds := DEFAULT_BUDGET_SECONDS
var started_msec := 0
var budget_exhausted: Dictionary = {}
## One receipt per shop visit: {town, gold_mode, gold_before, gold_after, purchases, skipped}.
var towns: Array = []
## Unit ids HSL_AUTOPLAY_STAT_SCALE already scaled (the carry keeps their attributes).
var scaled_units: Array = []
## Every attempt that ended in a dead_end: {level, try, seed, reason, detail}.
var dead_ends: Array = []
## Scenario path -> the carried damage stream its latest first attempt booted from ([] when the
## hand-off carries none: the loop then seeds the stream from the loop seed, which a retry changes).
var first_damage_words: Dictionary = {}
## Scenario path -> retry number k its next boot reseeds the carried damage stream with.
var damage_reseed_armed: Dictionary = {}
## Scenario path -> the k the pre-boot hook applied to the attempt now booting (0: carried as is).
var damage_reseed_applied: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## Fights one booted formal battle with the scored commander; answers the explorer with
## "handoff" (won, next scene pending), "retry" (lost, attempts left: the next loop seed is
## exported for the re-boot) or "stuck" (lost every attempt).
func _play_formal_battle(explorer: StoryExplorer, scene: Node) -> String:
	var path := str(scene.scenario_path)
	var level := CampaignProgress.level_key_for_scenario(campaign, path)
	var label := "level %d (%s)" % [level, path.get_file()]
	if budget_seconds > 0 and Time.get_ticks_msec() - started_msec >= budget_seconds * 1000:
		budget_exhausted = {"level": level, "scenario": path.get_file(), "budget_seconds": budget_seconds}
		print("CHAPTER_AUTOPLAY budget_exhausted at=%d budget_seconds=%d" % [level, budget_seconds])
		return StoryExplorer.OUTCOME_STUCK
	var attempts: Array = attempts_by_scenario.get(path, [])
	var seed := BASE_SEED + attempts.size()
	if attempts.is_empty():
		_keep_handoff(level)
	var damage_reseed := int(damage_reseed_applied.get(path, 0))
	damage_reseed_applied.erase(path)
	var damage_stream := "reseed:%d" % damage_reseed if damage_reseed > 0 else ("carried" if not (first_damage_words.get(path, []) as Array).is_empty() else "loop_seed")
	var note := func(condition: bool, message: String) -> void:
		if not condition:
			explorer.note("%s: %s" % [label, message])
	var party := _party_levels(scene.play_loop)
	var result: Dictionary
	if not bool(scene.play_loop.get("scenario_ok", false)):
		result = {"outcome": Autoplay.OUTCOME_DEAD_END, "battle_outcome": {}, "rounds": 0, "seconds": 0.0, "reason": Autoplay.REASON_EXCEPTION, "unit": "", "round": 0, "detail": "scenario_error=%s" % str(scene.play_loop.get("scenario_error", "")), "actions": {}, "result_page": false}
	else:
		await Autoplay.reach_first_control(self, scene, label, note)
		var scaled := Autoplay.apply_stat_scale(scene.play_loop, Autoplay.stat_scale_from_environment(), scaled_units)
		if not (scaled["scaled"] as Array).is_empty():
			scene.apply_loop(scaled["loop"], "test")
			scaled_units.append_array(scaled["scaled"])
		var brain := Brain.create(brain_mode)
		if budget_seconds > 0 and not brain.is_empty():
			brain["deadline_msec"] = started_msec + budget_seconds * 1000
		result = await Autoplay.play_battle(self, scene, Autoplay.DEFAULT_ROUND_LIMIT, seed, brain)
	# No wall clock in the file: a deterministic walk rewrites it byte-identically.
	var attempt := {"seed": seed, "outcome": str(result["outcome"]), "battle_outcome": result["battle_outcome"], "rounds": int(result["rounds"])}
	if damage_reseed > 0:
		attempt["damage_reseed"] = damage_reseed
	if str(result["outcome"]) == Autoplay.OUTCOME_DEAD_END:
		attempt["reason"] = str(result["reason"])
		attempt["detail"] = str(result["detail"])
	if result.has("brain"):
		attempt["plan_kinds"] = result["brain"]["plan_kinds"]
		if result["brain"].has("lookahead"):
			# Tracked output must be deterministic: keep the counters, drop the wall clock.
			var lookahead: Dictionary = (result["brain"]["lookahead"] as Dictionary).duplicate()
			lookahead.erase("sim_msec")
			attempt["lookahead"] = lookahead
	attempts.append(attempt)
	attempts_by_scenario[path] = attempts
	if str(result["outcome"]) == Autoplay.OUTCOME_DEAD_END:
		dead_ends.append({"level": level, "try": attempts.size(), "seed": seed, "reason": str(result["reason"]), "detail": str(result["detail"])})
	print("CHAPTER_AUTOPLAY_TRY level=%d try=%d seed=%d damage_stream=%s %s" % [level, attempts.size(), seed, damage_stream, Autoplay.format_line(str(level), result)])
	var won := str(result["outcome"]) == Autoplay.OUTCOME_WIN
	if not won and attempts.size() < tries_limit:
		OS.set_environment(Runtime.LOOP_SEED_ENV, str(BASE_SEED + attempts.size()))
		# The retry's global stream (AI, opening levels) restarts from the retry seed.
		GlobalRandom.reset_session()
		# ...and its carried damage stream is replaced before the re-boot (_reseed_retry_damage).
		damage_reseed_armed[path] = attempts.size()
		return StoryExplorer.OUTCOME_RETRY
	OS.set_environment(Runtime.LOOP_SEED_ENV, str(BASE_SEED))
	GlobalRandom.reset_session()
	attempts_by_scenario.erase(path)
	var row := {"level": level, "scenario": path.get_file(), "outcome": str(result["outcome"]), "battle_outcome": result["battle_outcome"], "tries": attempts.size(), "party": party, "attempts": attempts}
	battles.append(row)
	var reseeded := attempts.filter(func(row): return int(row.get("damage_reseed", 0)) > 0).size()
	print("CHAPTER_AUTOPLAY level=%d outcome=%s tries=%d retry_damage_reseed=%d battle_outcome=%s party=%s" % [level, str(result["outcome"]), attempts.size(), reseeded, BattleOutcome.describe(result["battle_outcome"]), JSON.stringify(party)])
	if not won:
		stuck_at = {"level": level, "scenario": path.get_file(), "outcome": str(result["outcome"]), "battle_outcome": result["battle_outcome"], "tries": attempts.size(), "party": party}
		if str(result["outcome"]) == Autoplay.OUTCOME_DEAD_END:
			stuck_at["reason"] = str(result["reason"])
			stuck_at["detail"] = str(result["detail"])
		return StoryExplorer.OUTCOME_STUCK
	if path not in EVENT_COMPLETION_BATTLES:
		var settled := _settle_blocked_loot(scene, level)
		if not settled.is_empty():
			row["loot_settled"] = settled
		# Like the result page's button: the hand-off is rebuilt from the finished loop, so
		# the carry holds this battle's growth and the win section's world writes reach the map.
		scene.campaign_progress.start_next_battle()
		await process_frame
	return StoryExplorer.OUTCOME_HANDOFF if CampaignProgress.has_pending() else StoryExplorer.OUTCOME_STUCK


## The explorer's pre-boot hook (its `goal`; never ends the walk). The explorer re-boots a retry
## from the very hand-off the lost attempt booted from, so without this every retry of a battle
## with a carried damage stream replays the same hits, damage and criticals and only the loop seed
## (AI, opening levels) changes. Retry k (1, 2, …) of such a battle instead boots with
## carry.damage_rng = DamageRandom.seeded(word0 ^ k), word0 the first word of the carried stream
## its first attempt booted from: a fresh, deterministic stream per battle and retry. A hand-off
## without a carried stream (the campaign start, the fresh-party start) is left alone: the loop
## seeds the stream from the loop seed, which the retry already changes. Harness only: the
## product's hand-off, save and restart keep the carried stream as it is.
func _reseed_retry_damage(_explorer: StoryExplorer, path: String) -> bool:
	var carry: Variant = CampaignProgress.pending.get("carry", {})
	var retry := int(damage_reseed_armed.get(path, 0))
	damage_reseed_armed.erase(path)
	if retry == 0:
		first_damage_words[path] = DamageRandom.from_words(carry.get(DamageRandom.LOOP_KEY) if carry is Dictionary else null)
		return false
	var words: Array = first_damage_words.get(path, [])
	if words.is_empty():
		return false
	carry[DamageRandom.LOOP_KEY] = DamageRandom.seeded(int(words[0]) ^ retry)
	damage_reseed_applied[path] = retry
	return false


## HSL_CHAPTER_HANDOFF_DIR=/abs/dir keeps the hand-off each battle booted from (the product's
## user://campaign_progress.json at the battle's first attempt) as `<dir>/<level>.json`, the file
## HSL_AUTOPLAY_HANDOFF replays one battle from (tests/run_autoplay_sweep_tests.gd).
func _keep_handoff(level: int) -> void:
	var directory := OS.get_environment(HANDOFF_DIR_ENV)
	if directory == "" or not FileAccess.file_exists(CampaignProgress.PROGRESS_PATH):
		return
	DirAccess.make_dir_recursive_absolute(directory)
	var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(CampaignProgress.PROGRESS_PATH), directory.path_join("%d.json" % level))
	_assert_true(copied == OK, "%s keeps the level %d hand-off (error %d)" % [HANDOFF_DIR_ENV, level, copied])


## The commander answers every in-battle loot panel with 「稍後」, so a won battle can end with a
## pending pool. An ordinary party carries it (保留物品並繼續); a separate party (level 53,
## 緼娜) cannot, and GrowthCampaignProgress.start_next_battle refuses the hand-off while
## the pool is pending. Do what a player leaving the result page does: reopen the panel,
## take what fits into a living controlled member's bag, 放棄 the rest. Returns {} when
## nothing was pending or the product would carry it; else {taken, abandoned, closed}.
func _settle_blocked_loot(scene: Node, level: int) -> Dictionary:
	var loop: Dictionary = scene.play_loop
	var pending: Array = loop.get("settlement", {}).get("pending", [])
	if pending.is_empty() or scene.campaign_progress.deferred_rewards_ready():
		return {}
	var reopened := Autoplay.Loop.reopen_rewards(loop)
	if Autoplay.Loop.same_state(reopened, loop):
		return {}
	loop = reopened
	var taken: Array = []
	for item in (loop["settlement"]["pending"] as Array).duplicate(true):
		for recipient in Autoplay.Loop.loot_recipients(loop):
			var claimed := Autoplay.Loop.claim_reward(loop, int(loop["settlement"]["sequence"]), int(loop["settlement"]["revision"]), str(item["id"]), str(recipient))
			if not Autoplay.Loop.same_state(claimed, loop):
				loop = claimed
				taken.append({"code": int(item["code"]), "recipient": str(recipient)})
				break
	var abandoned: Array = (loop["settlement"]["pending"] as Array).map(func(item): return int(item["code"]))
	var finished := Autoplay.Loop.finish_rewards(loop, int(loop["settlement"]["sequence"]), int(loop["settlement"]["revision"]), true, false)
	var closed := not Autoplay.Loop.same_state(finished, loop)
	if closed:
		loop = finished
	scene.apply_loop(loop, "test")
	var receipt := {"taken": taken, "abandoned": abandoned if closed else [], "closed": closed}
	print("CHAPTER_AUTOPLAY_LOOT level=%d taken=%s abandoned=%s closed=%s" % [level, JSON.stringify(taken), JSON.stringify(receipt["abandoned"]), str(closed)])
	return receipt


## The explorer's fresh-party start carries no member records until the first battle's
## capture, and a shop sells only to a recorded member (WorldPartyRules.buy): record the
## start scenario's roster in the carry with its bags only (actor id + inventory; levels,
## growth and equipment stay each battle's own until a purchase writes them) so the walk
## can shop before its first battle.
func _seed_fresh_party_records() -> void:
	var pending: Dictionary = CampaignProgress.pending
	var carry: Dictionary = pending["carry"]
	var template := str((campaign["battles"].get(FRESH_PARTY_TEMPLATE_LEVEL, {}) as Dictionary).get("scenario", ""))
	var scenario := BattleScenario.load_file(template)
	var box := PartyEquipment.sandbox(Autoplay.Loop.create([], "", scenario), carry)
	_assert_true(bool(box["ok"]), "the fresh-party template scenario %s boots a sandbox loop: %s" % [template.get_file(), str(box["error"])])
	if not bool(box["ok"]):
		return
	var records := {}
	for unit_id in CarryRules.capture(box["loop"])["units"]:
		var unit := Autoplay.Loop.unit(box["loop"], str(unit_id))
		records[str(unit_id)] = {"actor_id": str(unit.get("actor_id", "")), "attributes": {}, "inventory": unit.get("inventory", []).duplicate()}
	carry["units"] = records
	# The id the equipment sandbox looks up (PartyEquipmentRules.template_scenario_path).
	carry["from_scenario_id"] = str(scenario.get("id", ""))
	pending["carry"] = carry


## Shops in the town's open shop (StoryExplorer.shopper) and records the receipt.
func _shop(town: Node, town_id: int) -> void:
	var receipt := Shopping.shop(town, campaign)
	var row := {"town": town_id, "ok": bool(receipt["ok"]), "reason": str(receipt["reason"]), "gold_mode": str(receipt["gold_mode"]), "gold_before": int(receipt["gold_before"]), "gold_after": int(receipt["gold_after"]), "purchases": receipt["purchases"], "skipped": receipt["skipped"]}
	towns.append(row)
	print("CHAPTER_AUTOPLAY_SHOP town=%d ok=%s reason=%s gold=%d->%d purchases=%s skipped=%s" % [town_id, str(row["ok"]), str(row["reason"]), int(row["gold_before"]), int(row["gold_after"]), JSON.stringify(row["purchases"]), JSON.stringify(row["skipped"])])


## Levels known_dead_ends.json registers (the sweep asserts its schema; {} when unreadable).
func _known_dead_end_levels() -> Dictionary:
	var known := RegenDiff.parse_object(FileAccess.get_file_as_string(KNOWN_DEAD_ENDS_PATH)) if FileAccess.file_exists(KNOWN_DEAD_ENDS_PATH) else {}
	return known.get("levels", {}) if known.get("levels") is Dictionary else {}


## Controlled party at a battle's boot: unit id -> level.
func _party_levels(loop: Dictionary) -> Dictionary:
	var party := {}
	for unit in loop.get("units", []):
		if str(unit.get("battle_actor_role", "")) == "player_controlled":
			party[str(unit["id"])] = int(unit.get("level", 0))
	return party


func _run() -> void:
	campaign = CampaignProgress.load_campaign()
	CampaignProgress.resume_prompt_in_headless = false
	if OS.get_environment("HSL_CHAPTER_TRIES").is_valid_int():
		tries_limit = maxi(1, int(OS.get_environment("HSL_CHAPTER_TRIES")))
	OS.set_environment(Runtime.LOOP_SEED_ENV, str(BASE_SEED))
	GlobalRandom.reset_session()
	# The encounter dice and town events draw from the global RNG: seed it so the walk repeats.
	seed(BASE_SEED)
	if OS.get_environment("HSL_CHAPTER_START") == START_OHM_VILLAGE:
		start = START_OHM_VILLAGE
	if OS.get_environment("HSL_AUTOPLAY_BRAIN") in Brain.MODES:
		brain_mode = OS.get_environment("HSL_AUTOPLAY_BRAIN")
	if OS.get_environment("HSL_CHAPTER_BUDGET_SECONDS").is_valid_int():
		budget_seconds = maxi(0, int(OS.get_environment("HSL_CHAPTER_BUDGET_SECONDS")))
	var started := Time.get_ticks_msec()
	started_msec = started
	if start == START_OHM_VILLAGE:
		StoryExplorer.start_after_ohm_village()
		_seed_fresh_party_records()
	else:
		StoryExplorer.start_at_campaign_start()
	var explorer := StoryExplorer.new(self, _play_formal_battle)
	explorer.shopper = _shop
	explorer.goal = _reseed_retry_damage
	var outcome := await explorer.run()
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var wins := battles.filter(func(row): return str(row["outcome"]) == Autoplay.OUTCOME_WIN).size()
	# Replays recorded in the rows (`hsl check autoplay_chapter` recounts tries - 1 per row). The
	# explorer's own count also holds a replay the time budget cut before it started: that
	# battle's attempts never become a row, so the file and the PASS line count only the rows.
	var retries := 0
	for row in battles:
		retries += int(row["tries"]) - 1
	print("CHAPTER_AUTOPLAY_WALK steps=%d scenes=%d towns=%d retries=%d last=%s" % [explorer.steps, explorer.scenes_played.size(), explorer.towns_explored.size(), explorer.retries, outcome])
	print("CHAPTER_AUTOPLAY scenes: " + ", ".join(explorer.scenes_played))
	_assert_true(explorer.game_clear_reached or not stuck_at.is_empty() or not budget_exhausted.is_empty(), "the walk ends at GameClear, at a lost battle or at the time budget, not by exhaustion (%s): %s" % [outcome, " | ".join(explorer.log_lines.slice(maxi(0, explorer.log_lines.size() - 30)))])
	var payload := {"schema": SCHEMA, "brain": brain_mode, "policy": Brain.POLICIES[brain_mode], "tries_limit": tries_limit, "base_seed": BASE_SEED, "round_limit": Autoplay.DEFAULT_ROUND_LIMIT,
		"start": start, "start_note": "campaign: the campaign's start_level with no carry; ohm_village: the big map after 歐姆村 with a fresh party (the explorer's start); every later scene through the runtime's hand-offs (tests/support/StoryExplorer.gd)",
		"evidence_tier": "current-godot",
		"note": "The first chapter walked by the story explorer with every formal battle fought by the autoplay commander named in `brain` (tests/support/Autoplay.gd, tests/support/AutoplayBrain.gd) and the party's growth carried through the product hand-offs; a lost battle is replayed with the next loop seed up to tries_limit, and retry k of a hand-off that carries the damage stream boots with a fresh one (the attempt's damage_reseed k: seeded(first carried word ^ k)); a hand-off without one takes the stream from the loop seed. A run cut off by HSL_CHAPTER_BUDGET_SECONDS records the battle it did not start in budget_exhausted. The global RNG (encounter dice, town events) is seeded from base_seed, so one tree rewrites this file byte-identically. Not evidence about original balance.",
		"game_clear": explorer.game_clear_reached, "walk_outcome": outcome, "stuck_at": stuck_at, "budget_seconds": budget_seconds, "budget_exhausted": budget_exhausted,
		"knobs": {"gold": Shopping.gold_mode(), "stat_scale": Autoplay.stat_scale_from_environment()},
		"battles_fought": battles.size(), "battles_won": wins, "retries": retries, "scenes": explorer.scenes_played, "towns": towns, "battles": battles}
	var known := _known_dead_end_levels()
	var unknown_dead_ends := dead_ends.filter(func(row): return not known.has(str(row["level"])))
	_assert_true(unknown_dead_ends.is_empty(), "no attempt ends in a dead_end unless %s lists its level: %s" % [KNOWN_DEAD_ENDS_PATH, JSON.stringify(unknown_dead_ends)])
	var tracked := RegenDiff.parse_object(FileAccess.get_file_as_string(CHAPTER_PATH)) if FileAccess.file_exists(CHAPTER_PATH) else {}
	var drift := RegenDiff.differences(RegenDiff.chapter_headline(tracked), RegenDiff.chapter_headline(payload))
	var drifted: Array[String] = []
	for entry in drift:
		drifted.append(str(entry["path"]))
	var drift_lines: Array[String] = ["CHAPTER_AUTOPLAY_DRIFT fields=%s (%s rewritten and left in the worktree; its headline against the tracked file, never a failure)" % [str(drifted), CHAPTER_PATH.get_file()]]
	drift_lines.append_array(RegenDiff.field_lines(drift))
	print("\n".join(drift_lines))
	var file := FileAccess.open(CHAPTER_PATH, FileAccess.WRITE)
	_assert_true(file != null, "%s is writable" % CHAPTER_PATH)
	if file != null:
		file.store_string(JSON.stringify(payload, "  ", false) + "\n")
		file.close()
	await process_frame
	await TestSuite.settle_wall_clock(self, 0.3)
	var summary := "game_clear=%s stuck_at=%s budget_exhausted_at=%s start=%s brain=%s battles=%d won=%d retries=%d tries_limit=%d budget_seconds=%d seconds=%.1f" % [str(explorer.game_clear_reached), str(stuck_at.get("level", "")) if not stuck_at.is_empty() else "none", str(budget_exhausted.get("level", "")) if not budget_exhausted.is_empty() else "none", start, brain_mode, battles.size(), wins, retries, tries_limit, budget_seconds, seconds]
	if not stuck_at.is_empty():
		summary += " stuck_outcome=%s stuck_battle_outcome=%s" % [str(stuck_at["outcome"]), BattleOutcome.describe(stuck_at["battle_outcome"])]
		if stuck_at.has("reason"):
			summary += " stuck_reason=%s" % str(stuck_at["reason"])
	summary += " dead_ends=%d drift=%s" % [dead_ends.size(), ",".join(drifted) if not drifted.is_empty() else "none"]
	if failures.is_empty():
		print("CHAPTER_AUTOPLAY_PASS %s" % summary)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("CHAPTER_AUTOPLAY_FAIL count=%d %s" % [failures.size(), summary])
		quit(1)
