extends RefCounted
## Hand-drawn interface art over the imported one (docs/MODDING.md「界面」). An image under
## one of FOLDERS of content/imported/hsl/ is shown from the same relative path under the
## current campaign's `ui/` folder (beside its campaign.json; only for a campaign under
## content/authored/, the tree the public export ships), else under content/authored/ui/,
## else from the import itself. Chapter one's campaign.json (content/battles/) gets no
## campaign folder: it reads content/authored/ui/ only. The replacement keeps the name and the
## pixel size: layouts, hit rects and sheet regions stay those of the manifests. With neither
## folder holding the file the path comes back unchanged, so chapter one without authored art
## draws exactly the imported images. Resolved paths are cached per campaign; a campaign switch
## (the title's campaign board, a memoir of another campaign) starts a fresh cache. Screens
## resolve their art when they are built: the title screen is built before any campaign is
## entered, so its art comes from content/authored/ui/.
## provenance:
##   rules: remake-invented (mod override lookup; the replaced images keep their own provenance)
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")

const IMPORTED := "res://content/imported/hsl/"
## The interface folders an authored image may replace: panel parts and item icons, the
## battle UI shapes (panel boards, buttons, the I_RECT01 target frame), the command ring, the
## range cells and map cursor, the game cursor, the title／system menu art.
const FOLDERS := ["shared/panels/", "shared/shape_previews/battle_ui/", "shared/command_menu/", "shared/range_cells/", "shared/game_cursor/", "global/title/"]
## Every campaign's fallback (chapter one reads only this one).
const AUTHORED := "res://content/authored/ui/"
## Folder beside a campaign's campaign.json that wins over AUTHORED while that campaign runs,
## for campaigns under CAMPAIGN_TREE only.
const CAMPAIGN_FOLDER := "ui/"
const CAMPAIGN_TREE := "res://content/authored/"

static var _resolved: Dictionary = {}
static var _campaign := ""


## The file to load for the imported interface image `original` (a res:// path as the
## manifests list it); any other path is returned unchanged.
static func path(original: String) -> String:
	if CampaignProgress.campaign_path != _campaign:
		_resolved.clear()
		_campaign = CampaignProgress.campaign_path
	if not _resolved.has(original):
		_resolved[original] = _resolve(original)
	return _resolved[original]


## Loaded texture of path(original).
static func texture(original: String) -> Texture2D:
	return load(path(original))


static func _resolve(original: String) -> String:
	if not original.begins_with(IMPORTED):
		return original
	var relative := original.trim_prefix(IMPORTED)
	if not FOLDERS.any(func(folder: String) -> bool: return relative.begins_with(folder)):
		return original
	for root in [_campaign.get_base_dir().path_join(CAMPAIGN_FOLDER) if _campaign.begins_with(CAMPAIGN_TREE) else "", AUTHORED]:
		if root != "" and ResourceLoader.exists(root + relative):
			return root + relative
	return original
