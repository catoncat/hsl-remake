extends RefCounted
## Pure, source-mode-aware job stat terms, evaluated from the per-job formula table
## (content/generated/hsl/roles/job_formulas.json ← authored content/authored/roles/job_formulas.json).
## No job has a branch here: a new job is a table row. Equipment and current vitals are
## applied by the shared ProgressionRules refresh; no mutable actor lives here.
## provenance:
##   rules: resource-derived content/generated/hsl/roles/job_formulas.json; static-derived docs/evidence_packets/static_reverse/original_job_stats.md; static-derived docs/evidence_packets/static_reverse/original_player_mode_sides.md; runtime-measured docs/evidence_packets/runtime_observations/battle_053/README.md (swapped L1 023 = 28 HP); static-derived docs/evidence_packets/static_reverse/original_job_stats_91_99.md; static-derived docs/evidence_packets/static_reverse/original_mobile_jobs.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const MODEL := "native_job_stats_v1"
const FORMULAS_PATH := "res://content/generated/hsl/roles/job_formulas.json"
const FORMULAS_SCHEMA := "hsl_job_formulas.v1"
const ATTRIBUTES := ["str", "dex", "mind", "con"]
const STATS := ["max_hp", "max_mp", "attack", "defense", "speed"]
## items.json job_mask bit for a job is (job - JOB_MASK_BASE), as hsltools/data/equipment.py writes it.
const JOB_MASK_BASE := 80
## TYPE.H pmPlayer, the live +0x28 bit the 0x448840 hp_level term tests (ActorRoleRules.SIDE_PLAYER).
const SIDE_PLAYER := 0x10000

static var _cached_jobs: Dictionary = {}


## {job code string: formula row}; an unreadable table is empty, so every job is unsupported.
static func jobs() -> Dictionary:
	if _cached_jobs.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FORMULAS_PATH)) if FileAccess.file_exists(FORMULAS_PATH) else null
		if parsed is Dictionary and parsed.get("schema") == FORMULAS_SCHEMA and parsed.get("jobs") is Dictionary:
			_cached_jobs = parsed["jobs"]
	return _cached_jobs


static func has_job(job: int) -> bool:
	return jobs().has(str(job))


## Four base-attribute caps in str dex mind con order; {} for an unknown job.
static func caps(job: int) -> Dictionary:
	var row: Dictionary = jobs().get(str(job), {})
	var result := {}
	if row.has("caps"):
		for key in ATTRIBUTES:
			result[key] = int(row["caps"][key])
	return result


## Automatic five-point allocation quota per str dex mind con; [] for an unknown job.
static func allocation_quota(job: int) -> Array:
	var row: Dictionary = jobs().get(str(job), {})
	var result: Array = []
	for value in row.get("allocation_quota", []):
		result.append(int(value))
	return result


static func job_mask_bit(job: int) -> int:
	var shift := job - JOB_MASK_BASE
	return (1 << shift) if shift >= 0 and shift < 32 else 0


static func supported(profile: Dictionary) -> bool:
	var code: Variant = profile.get("job_code")
	return profile.get("model") == MODEL and typeof(code) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(code)) and code == int(code) and has_job(int(code))


## Integer sum of a term list: [mul, var, div] is mul*var/div, [mul, var, div, pre] is
## mul*(var/pre)/div, a bare number is a constant (integer division, left to right).
static func sum_terms(terms: Array, variables: Dictionary) -> int:
	var total := 0
	for term in terms:
		if term is Array:
			var value := int(variables[term[1]])
			if term.size() == 4:
				value = value / int(term[3])
			total += int(term[0]) * value / int(term[2])
		else:
			total += int(term)
	return total


## `side_mask` is the unit's live side bits (ActorRoleRules.side_mask: the installed
## player_mode, else the role-implied side). 0x448840 reads the hp_level term from the
## live +0x28 pmPlayer bit, not from the PLAYERS template mode: a 023 the constructor
## 0x407ec0 swapped to pmEnemy (obj_Data9) has no level term (L1 → 28 HP, runtime-measured
## docs/evidence_packets/runtime_observations/battle_053/original_units.json).
static func base_values(growth: Dictionary, attributes: Dictionary, level: int, side_mask: int) -> Dictionary:
	var row: Dictionary = jobs().get(str(int(growth["job_code"])), {})
	if row.is_empty():
		return {}
	var source: Dictionary = growth["source"]
	var variables := {"level": level}
	for key in ATTRIBUTES:
		variables[key] = int(attributes[key])
	variables["hp_level"] = level if side_mask & SIDE_PLAYER else 0
	var values := {}
	for stat in STATS:
		values[stat] = sum_terms(row[stat], variables)
	var magic_row: Dictionary = row["magic_attack"]
	var magic := sum_terms(magic_row["terms"], variables)
	if magic_row.has("cap"):
		magic = mini(magic, int(magic_row["cap"]))
	if magic_row.has("soft_knee") and magic > int(magic_row["soft_knee"]):
		magic = (magic - int(magic_row["soft_knee"])) / 2 + int(magic_row["soft_knee"])
	magic += int(magic_row["bonus"])
	var resists: Array = []
	var resist_cap := int(row["resist"]["cap"])
	for pair in row["resist"]["rows"]:
		resists.append(mini(resist_cap, int(pair[0]) * int(variables["mind"]) / 100 + int(variables["con"]) / int(pair[1])))
	return {"max_hp": int(values["max_hp"]) + int(source["hit_point"]), "max_mp": int(values["max_mp"]) + int(source["magic_point"]),
		"attack": int(values["attack"]) + int(source["attack_power"]) + level_attack_bonus(level),
		"defense": int(values["defense"]) + int(source["defense"]), "magic_attack": magic + int(source["magic_attack_power"]),
		"speed": int(values["speed"]) + int(source["speed"]), "resist_bonuses": resists}


static func level_attack_bonus(level: int) -> int:
	if level < 10: return maxi(0, level)
	if level < 20: return 10 + (level - 10) / 2
	return 15 + (level - 20) / 4
