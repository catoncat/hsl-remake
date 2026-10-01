extends SceneTree
## tools/web_packs.py build: writes every job's pack with PCKPacker — each [res path, source file]
## pair stored under its res path — in one headless run. Prints PACK_BUILDER_DONE.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var jobs: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0])) if not args.is_empty() else null
	if not jobs is Dictionary:
		push_error("pack_builder: missing or unreadable job file")
		quit(1)
		return
	var failed := 0
	for job in jobs["packs"]:
		var packer := PCKPacker.new()
		var err := packer.pck_start(str(job["out"]))
		for pair in job["files"]:
			if err != OK:
				break
			err = packer.add_file(str(pair[0]), str(pair[1]))
		if err == OK:
			err = packer.flush(false)
		if err != OK:
			push_error("pack_builder: %s failed (error %d)" % [job["id"], err])
			failed += 1
	print("PACK_BUILDER_DONE packs=%d failed=%d" % [jobs["packs"].size(), failed])
	quit(1 if failed > 0 else 0)
