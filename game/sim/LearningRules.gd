extends RefCounted
## Original player learners have no RNG. NPC auto-allocation is a different path.
## Records are immutable acquisitions; source declarations and gear are not edited.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_growth_lifecycle.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const POLICY := "source_growth_lifecycle_v1"
const Number = preload("res://game/sim/SkillResourceRules.gd")
const ATTRIBUTES := ["str", "dex", "mind", "con"]


static func basic_error(actor: Dictionary) -> String:
	var records: Variant = actor.get("learned_skills", [])
	if not records is Array or records.size() > 416: return "invalid_learned_skills"
	var seen := {}
	for record in records:
		if not record is Dictionary or record.get("policy") != POLICY or not record.get("id") is String or seen.has(record["id"]): return "invalid_skill_acquisition"
		if record.get("actor_id") != actor.get("actor_id") or not source_jobs(actor).has(Number._integer(record.get("job"))): return "learned_skill_source_mismatch"
		if Number._integer(record.get("level")) < 1 or int(record["level"]) > int(actor.get("level", 0)) or not record.get("attributes") is Dictionary: return "learned_skill_level_rollback"
		for key in ATTRIBUTES:
			if Number._integer(record["attributes"].get(key)) < 1 or int(record["attributes"][key]) > int(actor.get("combat_profile", {}).get(key, 0)): return "learned_skill_attribute_rollback"
		seen[record["id"]] = true
	return ""


static func input_error(actor: Dictionary, data: Dictionary) -> String:
	var basic := basic_error(actor)
	if basic != "": return basic
	if actor.get("learned_skills", []).is_empty(): return ""
	if data.get("schema") != "hsl_growth_lifecycle.v1" or data.get("policy") != POLICY: return "missing_learning_source"
	for record in actor["learned_skills"]:
		# A record keeps the job it was learned under; after a town job-up the
		# member's current job differs (0x4348f0 leaves the learned masks alone).
		var job: Dictionary = data.get("jobs", {}).get(str(int(record["job"])), {})
		var kind := "magic" if record["id"].begins_with("magic:") else "special"
		var matches: Array = job.get(kind, []).filter(func(row): return row["id"] == record["id"])
		if matches.size() != 1 or record.get("name") != matches[0]["name"] or record.get("trigger") != ("level_up" if kind == "magic" else "allocation"): return "invalid_learned_skill_rule"
		if not eligible(record, matches[0], kind, int(job.get("tier", 0))): return "unearned_skill"
		if declared(data.get("actors", {}).get(str(actor["actor_id"]), {}), record["id"]): return "duplicate_initial_skill_acquisition"
	return ""


## The current job plus every job the member held before a town job-up
## (JobUpRules.merge_source_template records from_job_code per step).
static func source_jobs(actor: Dictionary) -> Array:
	var jobs: Array = [Number._integer(actor.get("growth_profile", {}).get("job_code"))]
	for step in actor.get("job_up_history", []):
		if step is Dictionary and step.has("from_job_code"):
			jobs.append(Number._integer(step["from_job_code"]))
	return jobs


static func declared(masks: Dictionary, id: String) -> bool:
	var pieces := id.split(":")
	if pieces.size() != 3 or not pieces[2].begins_with("magicCode"): return false
	var code := pieces[2].trim_prefix("magicCode").to_int() - 1
	return code >= 0 and code < 32 and (int(masks.get(pieces[0] + ":" + pieces[1], 0)) & (1 << code)) != 0


static func eligible(record: Dictionary, rule: Dictionary, kind: String, tier: int) -> bool:
	if kind == "magic": return int(record["level"]) >= int(rule["level"])
	if tier < int(rule["tier"]): return false
	for key in ATTRIBUTES:
		if int(record["attributes"][key]) < int(rule["attributes"][key]): return false
	return true


static func acquire(actor: Dictionary, book: Dictionary, kind: String) -> Dictionary:
	var next := actor.duplicate(true)
	var added: Array = []
	if actor.get("growth_profile", {}).get("allocation") != "manual": return {"actor": next, "added": added}
	var data: Dictionary = book.get("learning", {})
	var job: Dictionary = data.get("jobs", {}).get(str(int(actor["growth_profile"]["job_code"])), {})
	var masks: Dictionary = data.get("actors", {}).get(str(actor["actor_id"]), {})
	var known: Array = book.get("actors", {}).get(str(actor["actor_id"]), {}).get("supported_initial_ids", []).duplicate()
	for record in actor.get("learned_skills", []): known.append(record["id"])
	var attrs := {}
	for key in ATTRIBUTES: attrs[key] = int(actor["combat_profile"][key])
	var record := {"policy": POLICY, "actor_id": actor["actor_id"], "job": int(actor["growth_profile"]["job_code"]),
		"level": int(actor["level"]), "attributes": attrs, "trigger": "level_up" if kind == "magic" else "allocation"}
	for rule in job.get(kind, []):
		if known.has(rule["id"]) or declared(masks, rule["id"]) or not eligible(record, rule, kind, int(job.get("tier", 0))): continue
		var acquired := record.duplicate(true)
		acquired.merge({"id": rule["id"], "name": rule["name"]})
		if not next.has("learned_skills"): next["learned_skills"] = []
		next["learned_skills"].append(acquired)
		added.append(acquired.duplicate(true))
		known.append(rule["id"])
		if kind == "special": break # Native preview/commit returns on its first missing eligible bit.
	return {"actor": next, "added": added}


static func owns(actor: Dictionary, id: String) -> bool:
	return actor.get("learned_skills", []).any(func(row): return row["id"] == id)


static func has_magic(actor: Dictionary) -> bool:
	return actor.get("learned_skills", []).any(func(row): return row["id"].begins_with("magic:"))


static func labels(records: Array, book: Dictionary) -> Array:
	return records.map(func(row): return "習得 " + row["name"] + ("（尚未可用）" if not book.get("skills", {}).has(row["id"]) else ""))
