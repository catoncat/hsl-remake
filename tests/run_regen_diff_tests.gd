extends "res://tests/support/TestSuite.gd"

## The autoplay sweep's regen-and-compare (tests/support/RegenDiff.gd regen_verdict with
## SWEEP_VERDICT_FIELDS) end to end on the tracked results.json: the sweep's int-typed rewrite
## that changes only one level's rounds is drift on exactly that level, never a failure (the
## old comparator's parsed-float against rebuilt-int over-report named every level); flipping
## that level's outcome fails naming exactly that level and field.

const RegenDiff = preload("res://tests/support/RegenDiff.gd")
const RESULTS_PATH := "res://content/generated/hsl/development/autoplay/results.json"


func _init() -> void:
	tag = "REGEN_DIFF_TESTS"


func run() -> void:
	var tracked := FileAccess.get_file_as_string(RESULTS_PATH)
	var parsed: Variant = JSON.parse_string(tracked)
	check(parsed is Dictionary and (parsed as Dictionary).get("levels") is Dictionary and not (parsed["levels"] as Dictionary).is_empty(), "%s parses with a levels object" % RESULTS_PATH)
	if not (parsed is Dictionary and (parsed as Dictionary).get("levels") is Dictionary and not (parsed["levels"] as Dictionary).is_empty()):
		return
	var document: Dictionary = RegenDiff.plain(parsed)
	var key: String = (document["levels"] as Dictionary).keys()[0]
	var level: Dictionary = document["levels"][key]
	level["rounds"] = int(level.get("rounds", 0)) + 1
	var drift := _verdict(tracked, document)
	check(drift["failure"] == "" and drift["changed"].is_empty() and drift["drifted"] == [key] and str(drift["drift"]).contains("levels/%s/rounds: " % key),
		"an int-typed rewrite changing only level %s's rounds is drift on that level alone, not a failure: %s %s" % [key, drift["failure"], drift["drifted"]])
	var old_outcome := str(level.get("outcome", ""))
	level["outcome"] = "fail" if old_outcome == "win" else "win"
	var flip := _verdict(tracked, document)
	check(flip["changed"] == [key] and str(flip["failure"]).contains("levels/%s/outcome: \"%s\" -> \"%s\"" % [key, old_outcome, level["outcome"]]),
		"an outcome flip fails naming level %s and the field: %s" % [key, flip["failure"]])


func _verdict(tracked: String, document: Dictionary) -> Dictionary:
	return RegenDiff.regen_verdict(RESULTS_PATH, tracked, _text(document), "levels", RegenDiff.SWEEP_VERDICT_FIELDS)


## The sweep's own serialisation (tests/run_autoplay_sweep_tests.gd _write_and_compare_results).
func _text(document: Dictionary) -> String:
	return JSON.stringify(document, "  ", false) + "\n"
