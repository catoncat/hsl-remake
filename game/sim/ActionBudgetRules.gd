extends RefCounted
## Pure command outcomes; no inventory, actor, queue or presentation ownership.
## Sources: original_action_state_machine.md, original_offense_completion.md,
## original_give_exchange.md. Call only after operation-specific validation.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_action_state_machine.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_offense_completion.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_give_exchange.md


static func command_available(operation: String, moved: bool, offense_completed: bool) -> bool:
	if offense_completed:
		return operation == "status"
	return not (operation == "move" and moved)


static func outcome(operation: String, give_used: bool = false) -> Dictionary:
	match operation:
		"select_move":
			return {"kind": "select_movement", "changes": {"interaction": "move_select"}}
		"select_attack", "select_special":
			return {"kind": "select_target", "changes": {"interaction": "attack_select", "selected_attack": operation.trim_prefix("select_")}}
		"select_magic":
			return {"kind": "keep_actor", "changes": {"interaction": "magic_select", "selected_attack": "magic"}}
		"move":
			return {"kind": "keep_actor", "changes": {"interaction": "action_menu", "moved_this_action": true, "pending_move": true}}
		"cancel_move":
			return {"kind": "restore_movement", "changes": {"interaction": "move_select", "moved_this_action": false, "pending_move": false, "selected_attack": "attack"}}
		"cancel_selection":
			return {"kind": "keep_actor", "changes": {"interaction": "action_menu", "selected_attack": "attack"}}
		"attack", "special", "magic":
			# Keep the owner selected while its immutable combat receipt is shown.
			return {"kind": "await_presentation", "changes": {"interaction": "action_menu", "attacked_this_action": true, "pending_move": false, "selected_attack": "attack"}}
		"wait", "use", "offense_presented":
			return {"kind": "end_action", "changes": {}}
		"give":
			return {"kind": "end_action" if give_used else "keep_actor", "changes": {}}
		"drop", "equip", "item", "status":
			return {"kind": "keep_actor", "changes": {}}
		_:
			push_error("Unknown action outcome: " + operation)
			return {"kind": "invalid", "changes": {}}


static func ends_action(operation: String, give_used: bool = false) -> bool:
	return outcome(operation, give_used)["kind"] in ["end_action", "await_presentation"]


static func give_used(previously_used: bool, sent: int, returned: int) -> bool:
	return previously_used or sent != returned
