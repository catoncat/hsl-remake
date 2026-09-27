extends SceneTree
## 开发用：直接进入指定战斗，跳过标题与战役存档。
##   tools/play.sh --script res://tests/play_battle.gd -- 003
## 参数是 content/battles/battle_NNN.json 的编号（3／003／--battle 003 都行）。
## 阵容用该战斗 JSON 的模板阵容（carry 为空，等同「開始新故事」直接跳到这一关），
## 不读也不写 CampaignProgress 的战役进度。


func _initialize() -> void:
	var id := ""
	for arg in OS.get_cmdline_user_args():
		var token := String(arg).lstrip("-")
		if token.is_valid_int():
			id = "%03d" % int(token)
	if id.is_empty():
		id = "051"
	var path := "res://content/battles/battle_%s.json" % id
	if not FileAccess.file_exists(path):
		push_error("play_battle: 找不到 %s" % path)
		quit(1)
		return
	print("PLAY_BATTLE scenario=%s" % path)
	preload("res://game/common/CampaignProgress.gd").pending = {"scenario_path": path, "carry": {}}
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
