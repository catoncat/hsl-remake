extends RefCounted

## Shared harness for Godot test suites.
##
## Rule suites (no scene boot, no real-time waits) `extends
## "res://tests/support/TestSuite.gd"`, set `tag`, implement `run()` and assert through
## check() / _assert_true() / _assert_eq(). tests/run_all.gd discovers them by that
## `extends` line, runs them in one Godot process and prints each suite's own result line
## (`TAG_PASS checks=N`), so a suite's PASS line and check count are the same whether it
## runs in the batch or alone (`run_all.gd -- run_x_tests.gd`).
##
## Static helpers serve every suite, including the scene suites that stay `extends
## SceneTree` and run one per process.
##
## Configuration freeze: tests/run_all.gd turns BattleLoopConfig.freeze_enabled on, so every
## BattlePlayLoop.create() records a hash of each CONFIG_SHARED block; assert_config_frozen()
## at the end of each rule suite re-hashes them and fails the suite naming any block a rule
## (or the suite) wrote in place — the shared blocks are read-only by contract.

const BattleLoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")

## Result-line prefix, e.g. "STAMINA_TESTS" → "STAMINA_TESTS_PASS checks=409".
var tag := ""
## Suites whose historical PASS line has no check count keep it bare ("CORE_RULE_TESTS_PASS").
var report_checks := true
var tree: SceneTree
var root: Window
var process_frame: Signal
var failures: Array[String] = []
var checks := 0


func attach(active_tree: SceneTree) -> void:
	tree = active_tree
	root = active_tree.root
	process_frame = active_tree.process_frame


## Override; may be a coroutine (`await` is allowed inside).
func run() -> void:
	failures.append("%s does not implement run()" % tag)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _assert_true(condition: bool, message: String) -> void:
	check(condition, message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	check(actual == expected, "%s expected=%s actual=%s" % [message, str(expected), str(actual)])


## Gives the caller its own deep copy of a shared configuration block to edit as fixture
## setup (`own(loop, "ai_profiles")["actors"]["026"]["profile"]["find_range"] = 0`): the block
## `loop` holds is replaced, the frozen original and every loop that shares it stay untouched.
## Writing into `loop[key]` directly would edit the shared block and fail assert_config_frozen.
static func own(loop: Dictionary, key: String) -> Variant:
	loop[key] = loop[key].duplicate(true)
	return loop[key]


## Random draws to hand a rule that takes an `rng: Callable`: `zero` always draws 0, `high` the
## top value `bound - 1`, and `no_rng` (rule suites) is a draw that must not happen — each call
## fails the suite, naming the suite line that led to it.
static func zero(_bound: int) -> int:
	return 0


static func high(bound: int) -> int:
	return maxi(0, bound - 1)


func no_rng(_bound: int) -> int:
	var at := ""
	for frame in get_stack():
		if str(frame.get("source", "")).contains("/tests/run_"):
			at = "%s:%d" % [str(frame["source"]).get_file(), int(frame["line"])]
			break
	check(false, "a rejected／skipped／terminal path drew RNG (%s)" % at)
	return 0


## The random streams a battle loop carries, by the name the helpers below take: tests read
## and set them through these helpers instead of the loop's internal keys.
## "reward" names the stream kill drops and birth carry draw: the global one (0x44f5d3／0x407c86).
const STREAM_KEYS := {"global": GlobalRandomStream.LOOP_KEY, "damage": DamageRandomStream.LOOP_KEY, "reward": GlobalRandomStream.LOOP_KEY}


## `loop`'s words of `stream` ("global", "damage" or "reward"); null when absent.
static func stream_of(loop: Dictionary, stream: String) -> Variant:
	return loop.get(STREAM_KEYS[stream])


static func set_stream(loop: Dictionary, stream: String, words: Variant) -> void:
	loop[STREAM_KEYS[stream]] = words


## Puts `loop`'s global or damage stream at the generator's seeded(`seed`) words.
static func seed_stream(loop: Dictionary, stream: String, seed: int) -> void:
	set_stream(loop, stream, GlobalRandomStream.seeded(seed) if stream == "global" else DamageRandomStream.seeded(seed))


## True when `after` holds `stream` where `before` left it: nothing between them drew.
static func no_draw(before: Dictionary, after: Dictionary, stream: String) -> bool:
	return stream_of(before, stream) == stream_of(after, stream)


## True when receipt `next` drew on exactly where receipt `previous` stopped.
static func continues(previous: Dictionary, next: Dictionary) -> bool:
	return next.get("rng_before") == previous.get("rng_after")


## True when a campaign carry (or a saved state) holds no global stream — neither the live
## words (0x4795d4／0x4795d8 are outside the original's save) nor the retired v5 key.
static func carries_no_stream(carry: Dictionary) -> bool:
	return not carry.has(GlobalRandomStream.LOOP_KEY) and not carry.has("initialization_rng")


## Fails the suite for every read-only configuration block written in place since the
## registry was last cleared (a failure, not a check, so the PASS check count is the same
## with or without the freeze). Clears the registry for the next suite.
func assert_config_frozen() -> void:
	for key in BattleLoopConfig.thaw():
		failures.append("%s wrote the shared configuration block %s in place" % [tag, str(key)])


func result_line() -> String:
	if failures.is_empty():
		return "%s_PASS checks=%d" % [tag, checks] if report_checks else "%s_PASS" % tag
	return "%s_FAIL count=%d checks=%d" % [tag, failures.size(), checks]


## Advances process frames until `condition` holds, at most `max_frames` (a frame count,
## not seconds, so the wait is the same under `--fixed-fps` and the real clock). Replaces
## "await process_frame ×N, then assert scene progress": on the real clock the first frame
## after a scene boot carries the whole load time as delta and pushes the opening timeline
## far ahead, while a fixed-fps frame is 1/60 s. Returns true when the condition held; on
## expiry the caller's own assertion still runs and fails with its own message, so the
## caller appends `waited_for` to its failures to name what never happened.
static func await_condition(active_tree: SceneTree, condition: Callable, max_frames: int) -> bool:
	for _frame in range(max_frames):
		if condition.call():
			return true
		await active_tree.process_frame
	return bool(condition.call())


## Waits real seconds whatever the engine clock does. Under `--fixed-fps` every process
## step is 1/fps regardless of wall time (and SceneTreeTimer follows that clock even with
## ignore_time_scale), so a suite that must let the audio mixer thread release stopped
## streams before quitting has to spin on the wall clock.
static func settle_wall_clock(active_tree: SceneTree, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await active_tree.process_frame


## Upper bound, past the settle, on waiting for the AudioServer to free stopped playbacks.
const AUDIO_RELEASE_TIMEOUT_MSEC := 2000
## [WeakRef to an AudioStreamPlayback, label] for every playback stop_audio() stopped and
## settle_audio_before_quit() has not yet seen freed.
static var _stopped_audio: Array = []


## `player.stop()` for an AudioStreamPlayer／2D／3D that also remembers its playback (weakly),
## so settle_audio_before_quit() waits until the AudioServer has freed it. Scene suites use it
## where a fixture silences a player it started (the dev harness's BattleMusic).
static func stop_audio(player: Node) -> void:
	if player.has_stream_playback():
		var stream: AudioStream = player.stream
		_stopped_audio.append([weakref(player.get_stream_playback()), "%s %s" % [player.get_path(), stream.resource_path if stream != null else ""]])
	player.stop()


## A scene suite's last wait before quit(). The AudioServer frees a stopped playback only
## after its mixer thread has faded it out and a later main-thread frame has collected it;
## a process that quits first leaks it ("4 ObjectDB instances were leaked at exit": the
## AudioStreamOggVorbis, its playback and packet sequences; "resources still in use": the
## track). An engine-clock `await create_timer(0.3).timeout` cannot wait for that: the first
## frame after a long synchronous step (a scene fixture) carries the whole step as its delta,
## so the timer ends a few ms of wall time later. This stops every audio player still in the
## tree through stop_audio(), spins frames for at least `seconds` of wall time and then until
## every playback stop_audio() recorded is freed (at most AUDIO_RELEASE_TIMEOUT_MSEC more).
## Returns one failure per playback still held; the caller appends them to its failures.
static func settle_audio_before_quit(active_tree: SceneTree, seconds: float) -> Array[String]:
	for node in active_tree.root.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			stop_audio(node)
	var settled := Time.get_ticks_msec() + int(seconds * 1000.0)
	var give_up := settled + AUDIO_RELEASE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < give_up and (Time.get_ticks_msec() < settled or _stopped_audio.any(func(entry: Array) -> bool: return entry[0].get_ref() != null)):
		await active_tree.process_frame
	var held: Array[String] = []
	for entry in _stopped_audio:
		if entry[0].get_ref() != null:
			held.append("audio playback still held by the AudioServer at quit: %s" % entry[1])
			push_error(held.back())
	_stopped_audio.clear()
	return held
