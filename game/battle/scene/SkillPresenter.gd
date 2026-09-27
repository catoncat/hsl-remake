extends Node2D
## The cut-in's presenter contract. BattleCombatCutin keeps one instance per presentation
## module: the script player for every skill_effects/manifest.json row declared `script`, and
## one node per `dedicated_module` file the manifest names (`skill_ids` lists the rows routed
## to it). Each frame the cut-in asks the first presenter whose `matches(strike)` is true to
## `present(host, clip, elapsed)`; the presenter draws under the host's stage, fires the host's
## `released`／`impact` signals once each through `mark`, and returns true when the clip is
## over. A presenter reads the settled receipt and the host's mirrors; it never owns combat
## truth. Adding a skill presentation = a manifest row (+ a module file when the script
## player cannot play it).
## provenance:
##   rules: remake-invented (released／impact fire once each at the presenter's own schedule; the contract carries no clock of its own)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
var skill_ids: Array[String] = []


## The rows the manifest routes to this module (`dedicated_module`); the script player
## overrides this with its `script` rows.
func matches(strike: Dictionary) -> bool:
	return skill_ids.has(str(strike.get("skill_id", "")))


## False for presentations that draw on the map without the combat-animation actor rows
## (a caster or target outside the compact cut-in packet must still see the effect).
func needs_actor_art(_strike: Dictionary) -> bool:
	return true


## Draw this frame; true when the clip is complete and the cut-in may pop it.
func present(_host: CanvasLayer, _clip: Dictionary, _elapsed: float) -> bool:
	return true


## Fires `released` then `impact` once each when `elapsed` passes the schedule's marks
## (`{"release": s, "impact": s, "complete": s}` in the host's elapsed seconds); true once
## `complete` is reached.
static func mark(host: CanvasLayer, clip: Dictionary, elapsed: float, schedule: Dictionary) -> bool:
	if elapsed >= float(schedule["release"]) and not clip["release_emitted"]:
		clip["release_emitted"] = true
		host.released.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], clip["counter"])
	if elapsed >= float(schedule["impact"]) and not clip["impact_emitted"]:
		clip["impact_emitted"] = true
		host.impact.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], clip["counter"])
	return elapsed >= float(schedule["complete"])


## Map presentations show no cut-in actors, projectile or flash.
static func hide_actors(host: CanvasLayer) -> void:
	for sprite in [host.blade, host.flash_sprite, host.attacker_sprite, host.defender_sprite]:
		sprite.hide()
