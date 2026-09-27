extends "res://tests/support/TestSuite.gd"
const Initialize = preload("res://game/sim/ActorInitializationRules.gd")
const Growth = preload("res://game/sim/ProgressionRules.gd")
const Entry = preload("res://game/sim/EntryGrowthRules.gd")
const Equipment = preload("res://game/sim/EquipmentRules.gd")
const ELEMENTS := ["magicEARTH","magicWATER","magicAIR","magicFIRE","magicMIND","magicOTHER","magicOTHER2"]

## Actors whose template declares source.runtime_blockers (collected while iterating the
## packet): the remake refuses their source equipment at initialization instead of
## substituting another item, and only 008 carries unequipped native rows to compare.
var blocked_actors: Array = []


func _init() -> void:
	tag = "CAMPAIGN_ACTOR_TESTS"


static func load_data(path: String) -> Dictionary:
	return integral_values(JSON.parse_string(FileAccess.get_file_as_string("res://"+path)))

static func integral_values(value: Variant) -> Variant:
	# JSON numbers are floats in Godot. These source packets contain integer rules;
	# normalize before nested Dictionary/Array equality, which also compares types.
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = integral_values(value[key])
		return result
	if value is Array: return value.map(integral_values)
	if value is float and value == floor(value): return int(value)
	return value

func run() -> void:
	var packet := load_data("docs/evidence_packets/static_reverse/original_campaign_actors.json")
	var roles: Dictionary = load_data("content/generated/hsl/roles/profiles.json")["actors"]
	var equipment: Dictionary = load_data("content/generated/hsl/equipment/items.json")["items"]
	var progression: Dictionary = load_data("content/imported/hsl/chapter01/progression.json")["actors"]
	var book := load_data("content/generated/hsl/skills/initial_book.json")
	book["learning"] = load_data("content/generated/hsl/roles/growth_lifecycle.json")
	var ai := load_data("content/generated/hsl/ai/profiles.json")
	var entry_sources: Dictionary = load_data("content/generated/hsl/roles/entry_growth.json")["actors"]
	var templates := {}
	var initial_rows := 0
	for row in packet["stats"]:
		var c: Dictionary = row["input"]
		if c["name"] != "initial": continue
		var code: String = c["actor"]
		var data := load_data("content/generated/hsl/actors/"+code+".json")
		var actor: Dictionary = data["actor"].duplicate(true)
		actor["coord"] = Vector2i.ZERO
		var before := actor.duplicate(true)
		var prepared := Initialize.prepare(actor,book,ai,progression,{},equipment,0)
		check(actor == before,"initialization leaves source template immutable: "+code)
		var blockers: Array = data["source"].get("runtime_blockers", [])
		if not blockers.is_empty():
			# The template declares its own runtime blocker (source weapons whose attack_range
			# the reviewed equipment contract does not model: 008 range 32, 052 weapon 58,
			# 057 weapon 53, 058 weapon 57, 060 weapon 55). Initialization must refuse them
			# explicitly, never substitute; the numeric rows below run on the unarmed template.
			blocked_actors.append(code)
			check(not prepared["ok"] and prepared["reason"] == "unsupported_equipment","source blocker is explicit, not a silent substitute: "+code)
			actor["equipment"] = []
			prepared = Initialize.prepare(actor,book,ai,progression,{},equipment,0)
		check(prepared["ok"],"source actor initializes with complete dependencies: "+code)
		if not prepared["ok"]: continue
		templates[code] = prepared["actor"]
		initial_rows += 1
		check(prepared["actor"]["traversal"] == data["source"]["traversal"],"source traversal survives initialization: "+code)
		check(Growth.JobStats.supported(prepared["actor"]["growth_profile"]),"source numeric job is supported: "+code)
	check(templates.size() == initial_rows and initial_rows >= 25,"all requested and encounter source templates exist (%d)" % initial_rows)
	for row in packet["stats"]:
		var c: Dictionary = row["input"]
		if c["actor"] in blocked_actors and c["name"] != "unequipped": continue # Source weapon geometry has an explicit blocker; only 008 carries unequipped native rows.
		if not templates.has(c["actor"]): continue
		var actor: Dictionary = templates[c["actor"]].duplicate(true)
		actor["growth_profile"] = row["profile"].duplicate(true)
		actor["player_mode"] = int(row["profile"]["source"]["mode"]) # the native rows ran with live +0x28 = this word
		actor["combat_profile"].merge(c["attributes"],true)
		actor.merge({"hp":int(c["hp"]),"mp":int(c["mp"]),"level":int(c["level"]),"base_move_point":int(c["base_move"]),"equipment":[]},true)
		for i in range(6):
			if int(c["equipment"][i]): actor["equipment"].append({"slot":Equipment.SLOTS[i],"item_code":int(c["equipment"][i])})
		check(Growth.refresh_input_error(actor,equipment) == "","numeric input remains valid: "+str(c))
		for native in row["native"]:
			actor = Growth.refresh_growth_stats(actor,equipment)
			var expected: Dictionary = native["values"]
			for key in ["max_hp","max_mp","move_point"]: check(actor[key] == expected[key],"complete native refresh "+key)
			check(actor["hp"] == expected["current_hp"] and actor["mp"] == expected["current_mp"] and actor["live_speed"] == expected["speed"],"native current-resource clamps and speed")
			for pair in [["attack","live_attack_damage"],["defense","live_defense"],["magic_attack","live_magic_attack"],["hit_rate","live_hit_ratio"],["avoid_hit_ratio","avoid_hit_ratio"],["attack_back","attack_back"],["attack_damagex2","attack_damagex2"]]:
				check(actor["combat_profile"][pair[1]] == expected[pair[0]],"source refresh "+pair[0]+" ("+str(c["actor"])+" "+str(c["name"])+": "+str(actor["combat_profile"][pair[1]])+" vs "+str(expected[pair[0]])+")")
			check(actor["combat_profile"]["resist_by_type"] == expected["resist_by_type"],"native five resistance values ("+str(c["actor"])+" "+str(c["name"])+": "+str(actor["combat_profile"]["resist_by_type"])+" vs "+str(expected["resist_by_type"])+")")
	for row in packet["growth"]:
		var c: Dictionary = row["input"]
		var expected: Dictionary = row["native"]
		var profile: Dictionary = roles[c["actor"]]["profile"]
		if c["kind"] == "infer":
			check(Entry.inferred_level(c["attributes"]) == int(expected["level"]),"source level inference")
			continue
		if c["kind"] == "allocate":
			var allocation := Entry.allocate(c["attributes"],int(c["level"]),int(c["exp"]),mini(2000,(int(c["level"])+1)*50),profile["caps"],int(profile["job_code"]),int(c["points"]))
			check(allocation["attributes"] == expected["attributes"] and allocation["level"] == int(expected["level"]) and allocation["exp"] == int(expected["exp"]),"new job native quotas and cap fallback")
			continue
		var source: Dictionary = entry_sources[c["actor"]]
		var input := {"job":int(profile["job_code"]),"caps":profile["caps"],"attributes":c["attributes"],"level":int(c["level"]),"exp":int(c["exp"]),"stamina":int(c["stamina"]),"object_kind":int(c["object_kind"]),"parameters":[int(c["range"]),int(c["dispersion"])],"party_levels":c["party"],"gold":int(source["gold"]),"kill_exp":int(source["kill_exp"])}
		var cursor := [0]
		var proposal := Entry.propose(input,func(bound):
			check(cursor[0] < row["draws"].size(),"no extra birth draw")
			if cursor[0] >= row["draws"].size(): return 0
			var draw: Dictionary = row["draws"][cursor[0]]; cursor[0] += 1
			check(int(draw["bound"]) == bound,"original birth random bound")
			return int(draw["value"]))
		check(proposal["ok"] and cursor[0] == row["draws"].size(),"new job entry adjustment completes")
		if not proposal["ok"]: continue
		for key in ["level","exp","stamina","gold","kill_exp","attributes"]: check(proposal["result"][key] == expected[key],"original adjusted "+key)
		for key in Entry.SOURCE_KEYS: check(int(profile["source"][key])+int(proposal["result"]["source_gains"][key]) == int(expected["source"][key]),"independent birth source layer")
	learning_cases(packet,book)

func learning_cases(packet: Dictionary, book: Dictionary) -> void:
	for row in packet["learning"]:
		var c: Dictionary = row["input"]
		if c.get("preview",false): continue # The product commits after allocation; native preview is checked in Python.
		var sample := book.duplicate(true)
		var masks := {}
		for element in ELEMENTS: masks[c["kind"]+":"+element] = 0xffffffff if c["existing"] else 0
		sample["learning"]["actors"]["fixture"] = masks
		var attrs := {}
		for i in range(4): attrs[Entry.KEYS[i]] = int(c["attributes"][i])
		var actor := {"actor_id":"fixture","growth_profile":{"job_code":int(c["job"]),"allocation":"manual"},"level":int(c["level"])+1,"combat_profile":attrs,"learned_skills":[]}
		var acquired := Growth.Learning.acquire(actor,sample,c["kind"])
		var actual: Array = row["native"]["masks"].map(func(_x):return 0xffffffff if c["existing"] else 0)
		for learned in acquired["added"]:
			var pieces: PackedStringArray = learned["id"].split(":")
			actual[ELEMENTS.find(pieces[1])] |= 1 << (pieces[2].trim_prefix("magicCode").to_int()-1)
		check(actual == row["native"]["masks"],"native class learning order and masks: "+str(c))
		check(actor["learned_skills"].is_empty(),"learning leaves caller immutable")
