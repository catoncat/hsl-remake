extends RefCounted
## The 「偵測到戰役進度」 prompt CampaignProgress raises when the campaign's first battle boots
## fresh with a saved position further along: dim layer, WINDOW50 board, the saved scenario's
## title and the 「繼續」／「從第一戰重新開始」 buttons. Builds the nodes only; CampaignProgress
## connects the buttons, pauses the tree and frees the layer. Loaded by CampaignProgress at call
## time so the save／hand-off module (preloaded by GameOptions) does not pull in the UI skin.
## provenance:
##   layout: remake-invented (resume prompt placement)
##   strings: remake-invented (「繼續」／「從第一戰重新開始」)

const BattleUISkin = preload("res://game/common/BattleUISkin.gd")


## {layer, resume, restart}: the always-processing layer (added under `host`) and its two buttons.
static func build(host: Node, title: String) -> Dictionary:
	var layer := CanvasLayer.new()
	layer.name = "CampaignResume"
	layer.layer = 4
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var dim := ColorRect.new()
	dim.size = Vector2(640, 480)
	dim.color = Color(0, 0, 0, 0.72)
	layer.add_child(dim)
	BattleUISkin.board(layer, "WINDOW50", Vector2(150, 150)).size = Vector2(340, 190)
	var heading := BattleUISkin.label(layer, Vector2(0, 168), 20)
	heading.size = Vector2(640, 30)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.text = "偵測到戰役進度"
	var info := BattleUISkin.label(layer, Vector2(0, 204))
	info.size = Vector2(640, 26)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.text = "上次進行到：%s" % title
	var resume := BattleUISkin.button(layer, "繼續 · %s" % title, Vector2(190, 246), Vector2(260, 36))
	var restart := BattleUISkin.button(layer, "從第一戰重新開始", Vector2(190, 290), Vector2(260, 36))
	return {"layer": layer, "resume": resume, "restart": restart}
