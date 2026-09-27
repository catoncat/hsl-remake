extends "res://game/battle/runtime/CampaignProgress.gd"
## Battle-owned growth metadata around the shared campaign coordinator.
## Destination, story/world changes, party isolation and persistence stay in the
## parent. The adapter carries the sole PlayLoop's cursor and lets a finished
## ordinary-party victory carry its explicitly deferred, validated reward pool. A
## separate party (campaign `party: separate`) cannot carry its pool, so its battle end
## reopens the get-item window and the notice line says why instead of a silent gate.
## provenance:
##   rules: remake-invented
##     (deferred validated reward pool at a quiet ordinary-party victory; a separate party's pool must be taken or
##     abandoned before the hand-off)
##   strings: remake-invented (the separate-party notice line)

## Notice line while a separate party's pool holds the battle end — no engineering terms.
const SEPARATE_LOOT_PROMPT := "這支隊伍不會帶走戰利品，請先拿取或放棄，再前往下一戰。"


## A separate party won with items still in the pool: the pool cannot travel with that
## party (deferred_rewards_ready is false for it), so the battle end must say what to do.
func separate_loot_blocking() -> bool:
	if runtime == null or runtime.settlement_controller == null: return false
	var loop: Dictionary = runtime.play_loop
	if loop.get("settlement", {}).get("pending", []).is_empty(): return false
	if not BattleOutcome.won(loop) or not runtime.get_node("BattlePresentation").battle_finished: return false
	return separate_party(campaign, str(runtime.scenario_path))


func deferred_rewards_ready() -> bool:
	if runtime == null or runtime.settlement_controller == null: return false
	var loop: Dictionary = runtime.play_loop
	var settlement: Dictionary = loop.get("settlement", {})
	if settlement.get("pending", []).is_empty() or not settlement.get("closed", false): return false
	if not BattleOutcome.won(loop) or not runtime.get_node("BattlePresentation").battle_finished: return false
	if separate_party(campaign, str(runtime.scenario_path)) or not runtime.settlement_controller.quiet(): return false
	if runtime.BattlePlayLoop.reward_input_error(loop) != "": return false
	return str(next_destination(campaign, loop, str(runtime.scenario_path)).get("path", "")) != ""


## The finished victory's pool cannot travel (a separate party's, or one without a carriable
## destination): reopen the get-item window so it is taken or abandoned first; a separate
## party also gets the notice line. True while the battle end must wait.
func hold_for_loot() -> bool:
	if runtime == null or runtime.settlement_controller == null: return false
	if runtime.play_loop.get("settlement", {}).get("pending", []).is_empty() or deferred_rewards_ready(): return false
	var blocking := separate_loot_blocking()
	runtime.settlement_controller.open_rewards()
	if not runtime.BattlePlayLoop.loot_waiting(runtime.play_loop): return false
	if blocking: runtime.settlement_controller.announce(SEPARATE_LOOT_PROMPT)
	return true


func start_next_battle() -> bool:
	if runtime.play_loop.get("settlement", {}).get("pending", []).size() > 0 and not deferred_rewards_ready(): return false
	return super.start_next_battle()

func prepare_handoff() -> Dictionary:
	var handoff := super.prepare_handoff()
	if handoff.is_empty() or not separate_party(campaign, str(runtime.scenario_path)):
		return handoff
	var carry: Dictionary = handoff["carry"]
	if carry.is_empty():
		carry = {"schema":CarryRules.SCHEMA,"units":{},"loop":{},"restore_vitals":true}
	if carry.get("schema") == CarryRules.SCHEMA:
		CarryRules.keep_damage_stream(carry, runtime.play_loop)
		handoff["carry"] = carry
	return handoff
