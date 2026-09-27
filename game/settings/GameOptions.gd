extends RefCounted
## 重製選項 (docs/OPTIONS.md): the option registry and the value a read point acts on. One
## card per option in content/authored/options/remake_options.json — id, tier (experience／
## development), layer (rules／presentation／appearance, `info` when it shows the player
## something the original hides), values with their original and comfort ids, read points.
##
## Value order: the card's original value < campaign.json `option_defaults` < the player's
## choice. The choice is GameSettings `preset`: original follows the campaign defaults, comfort
## takes every card's comfort value, custom takes the rows stored in `presentation` (a row
## missing or no longer legal falls back to the campaign default). A card the campaign lists in
## `option_hidden` is not shown and stays at the campaign default. With no read point wired a
## card changes nothing; the default of every card is the original path, which is what gates,
## the original referee and autoplay run.
##
## Development seam: HSL_OPTIONS_PRESET=original|comfort replaces the player's choice in
## windowless runs (the comfort smoke); a windowed run ignores it and says so.
## provenance:
##   rules: remake-invented docs/OPTIONS.md
##     (option registry, value order code default < campaign option_defaults < player choice, presets,
##     HSL_OPTIONS_PRESET seam)

const GameSettings = preload("res://game/settings/GameSettings.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const REGISTRY_PATH := "res://content/authored/options/remake_options.json"
const SCHEMA := "hsl_remake_options.v1"
const PRESET_ORIGINAL := "original"
const PRESET_COMFORT := "comfort"
const PRESET_CUSTOM := "custom"
const PRESET_ENV := "HSL_OPTIONS_PRESET"
const TIERS := ["experience", "development"]
const LAYERS := ["rules", "presentation", "appearance"]

static var _registry: Dictionary = {}
static var _campaign_path := ""
static var _campaign_layer: Dictionary = {}
## The preset HSL_OPTIONS_PRESET forces for this process, or "" (read once when the script loads).
static var environment_preset: String = _read_environment_preset()


## {options: [card…] in registry order, by_id: {id: card}, page: page layout}. A card that
## breaks the template is a data error: reported and left out.
static func registry() -> Dictionary:
	if _registry.is_empty():
		_registry = _load_registry()
	return _registry


static func options() -> Array:
	return registry()["options"]


static func option(id: String) -> Dictionary:
	return (registry()["by_id"] as Dictionary).get(id, {})


static func page_layout() -> Dictionary:
	return registry()["page"]


## Cards the 重製選項 page lists: the experience tier, less the campaign's hidden ones.
static func listed_options() -> Array:
	return options().filter(func(card: Dictionary) -> bool:
		return str(card["tier"]) == "experience" and not is_hidden(str(card["id"])))


static func value_ids(card: Dictionary) -> Array:
	return (card["values"] as Array).map(func(entry: Dictionary) -> String: return str(entry["id"]))


static func value_entry(card: Dictionary, value_id: String) -> Dictionary:
	for entry in card["values"]:
		if str(entry["id"]) == value_id:
			return entry
	return {}


## {defaults: {id: value}, hidden: [id]} of the campaign this process plays
## (CampaignProgress.campaign_path); first chapter writes neither key.
static func campaign_layer() -> Dictionary:
	if _campaign_path != CampaignProgress.campaign_path or _campaign_layer.is_empty():
		_campaign_path = CampaignProgress.campaign_path
		_campaign_layer = _read_campaign_layer(CampaignProgress.load_campaign())
	return _campaign_layer


## True when the campaign names defaults of its own: the original preset then reads 作者默認.
static func campaign_has_defaults() -> bool:
	return not (campaign_layer()["defaults"] as Dictionary).is_empty()


static func is_hidden(id: String) -> bool:
	return (campaign_layer()["hidden"] as Array).has(id)


## The card's value under the campaign: its original value unless option_defaults names another.
static func default_value(id: String) -> String:
	var card := option(id)
	return str((campaign_layer()["defaults"] as Dictionary).get(id, card.get("original_value", "")))


## The value a preset gives a card: comfort → the comfort value, original → the campaign default.
static func preset_value(preset_id: String, id: String) -> String:
	if preset_id == PRESET_COMFORT:
		return str(option(id).get("comfort_value", ""))
	return default_value(id)


## The player's preset: HSL_OPTIONS_PRESET in a windowless run, else the stored one. A windowless
## run without the variable is a gate／test／export: it never reads the player's stored choice
## (docs/OPTIONS.md §7 "不设就是原版" — 2026-09-27 the player's user://settings.json said comfort and the
## headless presentation contract went red under the real HOME).
static func preset() -> String:
	if environment_preset != "":
		return environment_preset
	if DisplayServer.get_name() == "headless":
		return PRESET_ORIGINAL
	return str(GameSettings.get_value("preset"))


## The value a read point acts on (an unknown id is a caller bug: reported, "").
static func value(id: String) -> String:
	var card := option(id)
	if card.is_empty():
		push_error("GameOptions: unknown option %s" % id)
		return ""
	if is_hidden(id):
		return default_value(id)
	var chosen := preset()
	if chosen == PRESET_CUSTOM:
		var picked := str((GameSettings.get_value("presentation") as Dictionary).get(id, ""))
		return picked if value_ids(card).has(picked) else default_value(id)
	return preset_value(chosen, id)


## True while the card takes the original path (the read point's untouched branch).
static func is_original(id: String) -> bool:
	return value(id) == str(option(id).get("original_value", ""))


## A preset button (original or comfort; 自定 is reached by changing a row).
static func apply_preset(preset_id: String) -> void:
	if not preset_id in [PRESET_ORIGINAL, PRESET_COMFORT]:
		push_error("GameOptions: %s is not a preset button" % preset_id)
		return
	GameSettings.set_values({"preset": preset_id, "presentation": {}})


## One row changed: the page turns 自定 and every other listed row keeps the value it showed.
static func choose(id: String, value_id: String) -> void:
	var card := option(id)
	if card.is_empty() or not value_ids(card).has(value_id):
		push_error("GameOptions: %s has no value %s" % [id, value_id])
		return
	var rows := {}
	for listed in listed_options():
		rows[str(listed["id"])] = value(str(listed["id"]))
	rows[id] = value_id
	GameSettings.set_values({"preset": PRESET_CUSTOM, "presentation": rows})


static func summary() -> Dictionary:
	var values := {}
	for card in options():
		values[str(card["id"])] = value(str(card["id"]))
	return {
		"schema": "hsl_remake_options_state.v1",
		"preset": preset(),
		"environment_preset": environment_preset,
		"values": values,
		"campaign_defaults": (campaign_layer()["defaults"] as Dictionary).duplicate(),
		"hidden": (campaign_layer()["hidden"] as Array).duplicate(),
	}


static func _load_registry() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY_PATH)) if FileAccess.file_exists(REGISTRY_PATH) else null
	if not parsed is Dictionary or str(parsed.get("schema", "")) != SCHEMA or not parsed.get("options") is Array or not parsed.get("page") is Dictionary:
		push_error("GameOptions: option registry missing or not %s: %s" % [SCHEMA, REGISTRY_PATH])
		return {"options": [], "by_id": {}, "page": {}}
	var cards: Array = []
	var by_id := {}
	for card in parsed["options"]:
		var problem := _card_problem(card, by_id)
		if problem != "":
			push_error("GameOptions: %s: %s" % [REGISTRY_PATH, problem])
			continue
		cards.append(card)
		by_id[str(card["id"])] = card
	return {"options": cards, "by_id": by_id, "page": parsed["page"]}


static func _card_problem(card: Variant, seen: Dictionary) -> String:
	if not card is Dictionary or str(card.get("id", "")) == "":
		return "a card without an id"
	var id := str(card["id"])
	if seen.has(id):
		return "%s appears twice" % id
	if not str(card.get("tier", "")) in TIERS:
		return "%s tier %s is not %s" % [id, card.get("tier"), TIERS]
	if not str(card.get("layer", "")) in LAYERS:
		return "%s layer %s is not %s" % [id, card.get("layer"), LAYERS]
	if not card.get("values") is Array or (card["values"] as Array).is_empty():
		return "%s has no values" % id
	var ids: Array = []
	for entry in card["values"]:
		if not entry is Dictionary or str(entry.get("id", "")) == "" or ids.has(str(entry["id"])):
			return "%s has a value without a unique id" % id
		ids.append(str(entry["id"]))
	for key in ["original_value", "comfort_value"]:
		if not ids.has(str(card.get(key, ""))):
			return "%s %s %s is not one of its values %s" % [id, key, card.get(key), ids]
	return ""


static func _read_campaign_layer(campaign: Dictionary) -> Dictionary:
	var defaults := {}
	var hidden: Array = []
	var raw_defaults: Variant = campaign.get("option_defaults", {})
	if not raw_defaults is Dictionary:
		push_error("GameOptions: campaign option_defaults must map option ids to value ids")
		raw_defaults = {}
	for id in raw_defaults:
		var card := option(str(id))
		if card.is_empty() or not value_ids(card).has(str(raw_defaults[id])):
			push_error("GameOptions: campaign option_defaults %s=%s names no registered option value" % [id, raw_defaults[id]])
			continue
		defaults[str(id)] = str(raw_defaults[id])
	var raw_hidden: Variant = campaign.get("option_hidden", [])
	if not raw_hidden is Array:
		push_error("GameOptions: campaign option_hidden must list option ids")
		raw_hidden = []
	for id in raw_hidden:
		if option(str(id)).is_empty():
			push_error("GameOptions: campaign option_hidden names unknown option %s" % id)
			continue
		hidden.append(str(id))
	return {"defaults": defaults, "hidden": hidden}


static func _read_environment_preset() -> String:
	var raw := OS.get_environment(PRESET_ENV).strip_edges()
	if raw == "":
		return ""
	if not raw in [PRESET_ORIGINAL, PRESET_COMFORT]:
		push_error("%s must be %s or %s, got %s; the player's choice stands" % [PRESET_ENV, PRESET_ORIGINAL, PRESET_COMFORT, raw])
		return ""
	if DisplayServer.get_name() != "headless":
		print("%s=%s ignored: windowless runs only; the 重製選項 page decides" % [PRESET_ENV, raw])
		return ""
	print("OPTIONS_PRESET_OVERRIDE %s=%s" % [PRESET_ENV, raw])
	return raw
