extends SceneTree

## Story-mode explorer: from the big map after the 歐姆村 battle, walks the whole game the
## way a player in story mode would, without a hand-authored route — travels to every
## reachable point, exhausts every town menu (dialogue confirmed, prompts answered with
## their first row, shops closed), plays every scene it is handed (formal battles through
## the shared force-win fixture tests/support/BattleForceWin.gd, the first row of any
## prompt) — until the GameClear sequence appears or nothing new can be reached. Proves that the registered scenes,
## the map reveals and the town chains connect from the first field battle to the ending
## through the product's own hand-offs; it does not prove any battle or original pacing.
## Encounter dice are the runtime's own (seeded from HSL_RNG_SEED when it is set); a registered encounter (501-506) is played through
## the formal-battle fixture, an unregistered one leaves the party on the map with a card,
## so the walk continues either way. The main walk must meet the milestone set below and
## reach GameClear. The coverage passes (PASSES) then walk what a first-row walk cannot
## reach — the prologue (51 → 52 → STORY058 → STORY060 → 53 → 1), the 艾瓦台地 branch
## (STORY067) and the finales 77 / 78 — and the suite fails unless the union of all walks
## covers every campaign.json story scene and every finale chain to GameClear
## (STORY_MODE_EXPLORER_COVERAGE story_scenes=N/N endings=3/3). Random encounters are
## not counted: the covered set is the registered story scenes, not the scene count, which
## moves with the encounter dice (56–62). 2026-09-24: main walk 57 scenes / 22 town
## exhaustions ~90 s, the four passes ~20 s, under --fixed-fps 60.
## Runs in the deep gate (tools/verify.sh --deep), not in the fast gate.
## Set HSL_EXPLORER_ENDING=76, 77, or 78 to skip the walk and passes: that finale is
## injected into a synthetic STORY057 hand-off and its chain walked to GameClear.
## The walk itself (map BFS, town exhaustion, scene playback) is tests/support/StoryExplorer.gd,
## shared with run_chapter_autoplay_tests.gd, which fights the battles instead.

const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const BattleForceWin = preload("res://tests/support/BattleForceWin.gd")
const StoryExplorer = preload("res://tests/support/StoryExplorer.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")


func _initialize() -> void:
	call_deferred("_run")


## A registered formal battle (the coordinator is not in story mode): the explorer does
## not fight — it plays the opening to first control and force-wins through the shared
## fixture tests/support/BattleForceWin.gd (the level's `sweep_fixture` in
## content/battles/levels/NNN.json, the same source-timed victories the battle sweep
## asserts), then takes the campaign's next scene like the result page's button. Levels
## whose script ends by event completion (73／78) arm their own hand-off.
## A fixture for map / story traversal, not battle evidence.
func _play_formal_battle(explorer: StoryExplorer, scene: Node) -> String:
	var label := "battle %s" % str(scene.scenario_path).get_file()
	var note := func(condition: bool, message: String) -> void:
		if not condition:
			explorer.note("%s: %s" % [label, message])
	var event_completion := BattleForceWin.arms_own_handoff(scene)
	if not BattleForceWin.skips_opening(scene):
		# An event-only battle (73) opens its choice from the battle entry, no first-control phase.
		await BattleForceWin.play_opening(self, scene, label, note)
	var won := await BattleForceWin.force_win(self, scene, label, note)
	if not won:
		explorer.note("battle: no victory result (outcome %s)" % BattleOutcome.of(scene.play_loop))
		return StoryExplorer.OUTCOME_STUCK
	if not event_completion:
		# Like the result page's button — and like the sweep — the hand-off is rebuilt from
		# the finished loop here, so the win section's world writes (pending_world_flags)
		# reach the map even when an earlier event cutscene already armed a hand-off.
		scene.campaign_progress.start_next_battle()
		await process_frame
	return StoryExplorer.OUTCOME_HANDOFF if CampaignProgress.has_pending() else StoryExplorer.OUTCOME_STUCK


## The coverage passes after the main walk. The main walk takes the first row of every
## prompt and so one branch at each fork; each pass below walks a scene the main walk cannot
## reach, from the campaign start or from a hand-off the main walk recorded:
##   prologue — the campaign's start_level (51) through 52 → STORY058 → STORY060 → 53 → 1 to
##     the big map where the main walk starts (the main walk begins after 歐姆村);
##   harbour_declined — from the main walk's big-map hand-off after 900, every town prompt
##     takes its last row on first sighting: 薛維斯港's captain (TOWNDEF 48) is declined, so the
##     party does not sail to 命運神殿 (TOWNDEF 53 teBMSetPointEventNotVisit 17,902) and plays
##     艾瓦台地 17 itself → STORY067; ends once STORY067 has handed off;
##   ending_77 / ending_78 — from the main walk's own STORY057 hand-off with the over score /
##     flag that dispatch 77 / 78 injected (the flags come from WINFAIL073's release choice and
##     WINFAIL037's enemy job-up, which the force-win fixtures skip), walked to GameClear.
## Each entry: name, start ("campaign" or a recorded hand-off {path, after}), knobs, and the
## scenes that must be played for the pass to count (`expect`, with GameClear as
## GAME_CLEAR_SCENE).
const GAME_CLEAR_SCENE := "GameClearScreen.tscn"
const PASSES := [
	{"name": "prologue", "start": "campaign", "goal": "map", "expect": ["battle_051.json", "battle_052.json", "story_058.json", "story_060.json", "battle_053.json"]},
	{"name": "harbour_declined", "start": {"path": StoryExplorer.MAP_SCENE, "after": "battle_900.json"}, "prompt_last_row": true, "goal": "story_067.json", "expect": ["battle_017.json", "story_067.json"]},
	{"name": "ending_77", "start": {"path": StoryExplorer.STORY_057, "after": ""}, "ending": "77", "expect": ["story_057.json", "battle_077.json", "story_082.json", GAME_CLEAR_SCENE]},
	{"name": "ending_78", "start": {"path": StoryExplorer.STORY_057, "after": ""}, "ending": "78", "expect": ["story_057.json", "battle_078.json", "battle_079.json", GAME_CLEAR_SCENE]},
]
## The three finales STORY057 dispatches (EndingDispatchRules.FINALS) and the chain each must
## walk to GameClear, whichever pass walks it.
const ENDING_CHAINS := {
	"76": ["story_057.json", "battle_076.json", "story_081.json", "battle_059.json", GAME_CLEAR_SCENE],
	"77": ["story_057.json", "battle_077.json", "story_082.json", GAME_CLEAR_SCENE],
	"78": ["story_057.json", "battle_078.json", "battle_079.json", GAME_CLEAR_SCENE],
}


## The scenes an explorer walked, GameClear included however it was entered (a story scene's
## game_clear record or a battle's result page leaves no GameClear hand-off to boot).
static func walked(explorer: StoryExplorer) -> Array:
	var scenes: Array = Array(explorer.scenes_played)
	if explorer.game_clear_reached and not scenes.has(GAME_CLEAR_SCENE):
		scenes.append(GAME_CLEAR_SCENE)
	return scenes


## Registered story scenes (campaign.json kind=story), as scenario file names.
static func registered_story_scenes() -> Array:
	var names: Array = []
	var campaign := CampaignProgress.load_campaign()
	for key in campaign.get("battles", {}):
		if str(campaign["battles"][key].get("kind", "")) == "story":
			names.append(str(campaign["battles"][key].get("scenario", "")).get_file())
	names.sort()
	return names


func _run() -> void:
	# Finale QA starts from the already-reached STORY057 hand-off; the default
	# explorer remains the full map BFS when HSL_EXPLORER_ENDING is unset.
	var started_msec := Time.get_ticks_msec()
	# The encounter dice (WorldMapRules.arrival) roll the engine's global randi(), which the
	# engine seeds from the clock: under HSL_RNG_SEED (the gate sets it) the walk takes the
	# same encounters on every run, so two runs print the same walked lists.
	var rng_seed := OS.get_environment("HSL_RNG_SEED").strip_edges()
	if rng_seed.is_valid_int():
		seed(int(rng_seed))
	# No Engine.time_scale fast-forward: at 16× the formal battles took a third of the frames
	# at ~3.5× the cost per frame and the walk was no faster (STORY_MODE_EXPLORER_TIMING, 1×
	# against 16×); the time goes to the game's own work per second of play, not to frames.
	StoryExplorer.start_after_ohm_village()
	var explorer := StoryExplorer.new(self, _play_formal_battle)
	var outcome := await explorer.run()
	var main_seconds := (Time.get_ticks_msec() - started_msec) / 1000.0
	var scenes_played := explorer.scenes_played
	var game_clear_reached := explorer.game_clear_reached
	var requested_ending := explorer.requested_ending
	print("STORY_MODE_EXPLORER steps=%d scenes=%d towns=%d game_clear=%s last=%s seconds=%.1f" % [explorer.steps, scenes_played.size(), explorer.towns_explored.size(), str(game_clear_reached), outcome, main_seconds])
	print("STORY_MODE_EXPLORER scenes: " + ", ".join(scenes_played))
	print("STORY_MODE_EXPLORER_TIMING main " + explorer.timing_line())
	var tail := explorer.log_lines.slice(maxi(0, explorer.log_lines.size() - 30))
	print("STORY_MODE_EXPLORER tail: " + " | ".join(tail))
	await process_frame
	print("STORY_MODE_EXPLORER unreached by the main walk: " + ", ".join(explorer.unreached_story_scenes()))
	if not requested_ending.is_empty() or explorer.ending in StoryExplorer.ENDINGS:
		await _finish_direct_ending(explorer, outcome)
		return
	# Each milestone lists its alternatives: a party that visited 命運神殿 first is sent
	# into the side-route battles (TOWNDEF 53 → 902, whose victory hangs 904 on point 19),
	# so 利魯瑪山地 is reached as level 19 or as level 904. Levels remade as formal battles
	# are played as battle_NNN.json; their story_NNN.json preview names stay accepted so an
	# older campaign registration still counts.
	var milestones := [["gol_road_battle.json"], ["story_056.json"], ["story_061.json"], ["battle_006.json"], ["story_063.json"], ["story_066.json"], ["battle_901.json", "story_901.json"], ["battle_900.json", "story_900.json"], ["battle_019.json", "battle_904.json", "story_019.json", "story_904.json"], ["story_069.json"], ["battle_034.json", "story_034.json"], ["battle_045.json", "story_045.json"], ["battle_075.json", "story_075.json"], ["story_057.json"]]
	var missing: Array = milestones.filter(func(names): return not names.any(func(name): return scenes_played.has(name))).map(func(names): return "/".join(names))
	var failures: Array = []
	if not missing.is_empty():
		failures.append("main walk misses milestones %s" % ", ".join(missing))
	if not game_clear_reached:
		failures.append("main walk ended %s without GameClear" % outcome)
	# Coverage passes: every registered story scene and every finale, each with its outcome.
	var walks := {"main": walked(explorer)}
	var pass_failures := {}
	for spec_value in PASSES:
		var spec: Dictionary = spec_value
		var name := str(spec["name"])
		var pass_started := Time.get_ticks_msec()
		var coverage_pass := StoryExplorer.new(self, _play_formal_battle)
		coverage_pass.ending = str(spec.get("ending", ""))
		coverage_pass.prompt_last_row = bool(spec.get("prompt_last_row", false))
		var goal := str(spec.get("goal", ""))
		if goal == "map":
			coverage_pass.goal = func(_walk, path: String) -> bool: return path == StoryExplorer.MAP_SCENE
		elif goal != "":
			coverage_pass.goal = func(walk, _path: String) -> bool: return walk.scenes_played.has(goal)
		var start: Variant = spec["start"]
		var pass_outcome := "not_started"
		if typeof(start) == TYPE_STRING and start == "campaign":
			StoryExplorer.start_at_campaign_start()
			pass_outcome = await coverage_pass.run()
		else:
			var handoff := explorer.handoff_into(str(start["path"]), str(start["after"]))
			if handoff.is_empty():
				coverage_pass.note("the main walk recorded no hand-off into %s after %s" % [str(start["path"]).get_file(), str(start["after"])])
			else:
				StoryExplorer.start_from_handoff(handoff)
				pass_outcome = await coverage_pass.run()
		CampaignProgress.pending = {}
		var scenes := walked(coverage_pass)
		walks[name] = scenes
		var expected: Array = spec["expect"]
		var absent: Array = expected.filter(func(scene_name): return not scenes.has(scene_name))
		var wanted_outcome := StoryExplorer.OUTCOME_GOAL if goal != "" else StoryExplorer.OUTCOME_GAME_CLEAR
		var ok: bool = absent.is_empty() and pass_outcome == wanted_outcome
		print("STORY_MODE_EXPLORER_WALK name=%s outcome=%s ok=%s steps=%d scenes=%d seconds=%.1f walked=%s" % [name, pass_outcome, str(ok), coverage_pass.steps, scenes.size(), (Time.get_ticks_msec() - pass_started) / 1000.0, ", ".join(scenes)])
		if not ok:
			failures.append("walk %s: outcome %s (want %s), not walked %s" % [name, pass_outcome, wanted_outcome, ", ".join(absent)])
			pass_failures[name] = coverage_pass.log_lines
		await TestSuite.settle_wall_clock(self, 0.05)
	# Coverage: the union of the walks against campaign.json's story scenes and the finales.
	var union: Dictionary = {}
	for name in walks:
		for scene_name in walks[name]:
			union[scene_name] = true
	var story_scenes := registered_story_scenes()
	var story_walked: Array = story_scenes.filter(func(scene_name): return union.has(scene_name))
	var story_missing: Array = story_scenes.filter(func(scene_name): return not union.has(scene_name))
	var endings_walked: Array = []
	for final_level in ENDING_CHAINS:
		var chain: Array = ENDING_CHAINS[final_level]
		for name in walks:
			if chain.all(func(scene_name): return (walks[name] as Array).has(scene_name)):
				endings_walked.append("%s(%s)" % [final_level, name])
				break
	var endings_missing: Array = ENDING_CHAINS.keys().filter(func(final_level): return not endings_walked.any(func(entry): return str(entry).begins_with(final_level + "(")))
	if not story_missing.is_empty():
		failures.append("story scenes not walked: %s" % ", ".join(story_missing))
	if not endings_missing.is_empty():
		failures.append("endings not walked to GameClear: %s" % ", ".join(endings_missing))
	print("STORY_MODE_EXPLORER story scenes walked: " + ", ".join(story_walked))
	print("STORY_MODE_EXPLORER_COVERAGE story_scenes=%d/%d endings=%d/%d endings_walked=%s story_missing=%s seconds=%.1f" % [story_walked.size(), story_scenes.size(), endings_walked.size(), ENDING_CHAINS.size(), ",".join(endings_walked), ",".join(story_missing), (Time.get_ticks_msec() - started_msec) / 1000.0])
	await process_frame
	# Wall-clock settle: under --fixed-fps the audio thread still needs real time to
	# release the stopped streams before quit (see tests/README「快钟」).
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("STORY_MODE_EXPLORER_PASS scenes=%d game_clear=%s ending= story_scenes=%d/%d endings=%d/%d" % [scenes_played.size(), str(game_clear_reached), story_walked.size(), story_scenes.size(), endings_walked.size(), ENDING_CHAINS.size()])
		quit(0)
	else:
		# The 30-line tail rarely shows where a walk went wrong; a failure prints every step.
		print("STORY_MODE_EXPLORER steps: " + " | ".join(explorer.log_lines))
		for name in pass_failures:
			print("STORY_MODE_EXPLORER steps %s: %s" % [name, " | ".join(pass_failures[name])])
		print("STORY_MODE_EXPLORER_FAIL outcome=%s %s" % [outcome, "; ".join(failures)])
		quit(1)


## HSL_EXPLORER_ENDING=76|77|78: the walk started at a synthetic STORY057 hand-off
## (start_after_ohm_village) with that finale injected; passes when its chain reaches GameClear.
func _finish_direct_ending(explorer: StoryExplorer, outcome: String) -> void:
	var requested_ending := explorer.requested_ending
	var scenes := walked(explorer)
	var chain: Array = ENDING_CHAINS.get(requested_ending, [])
	var finale_chain_ok: bool = not chain.is_empty() and explorer.game_clear_reached and chain.all(func(name): return scenes.has(name))
	await TestSuite.settle_wall_clock(self, 0.2)
	if finale_chain_ok:
		print("STORY_MODE_EXPLORER_PASS scenes=%d game_clear=%s ending=%s" % [explorer.scenes_played.size(), str(explorer.game_clear_reached), requested_ending])
		quit(0)
	else:
		print("STORY_MODE_EXPLORER steps: " + " | ".join(explorer.log_lines))
		print("STORY_MODE_EXPLORER_FAIL outcome=%s ending=%s chain_ok=%s" % [outcome, requested_ending, str(finale_chain_ok)])
		quit(1)
