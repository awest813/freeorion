class_name AutoTurnGuard
extends RefCounted
## Automatic turn advance stops itself when the empire is in danger, so a
## player away from the keys doesn't come back to a lost game: own planets
## lost, own ships destroyed, a battle or invasion the empire was in, a
## planet depopulated. check() says why, once per turn.

## Sitrep label -> why auto end turn stopped.
const SITREP_REASONS := {
	"SITREP_COMBAT_SYSTEM_LABEL": "AUTO_TURN_STOP_COMBAT",
	"SITREP_COMBAT_SYSTEM_ENEMY_LABEL": "AUTO_TURN_STOP_COMBAT",
	"SITREP_GROUND_BATTLE_LABEL": "AUTO_TURN_STOP_INVASION",
	"SITREP_GROUND_BATTLE_ENEMY_LABEL": "AUTO_TURN_STOP_INVASION",
	"SITREP_OWN_SHIP_DESTROYED_AT_SYSTEM_LABEL": "AUTO_TURN_STOP_SHIP_LOST",
	"SITREP_PLANET_DEPOPULATED_LABEL": "AUTO_TURN_STOP_DEPOPULATED",
}

## Own planets last turn (-1 before the first check).
var _planets := -1


## The text key saying why auto end turn should stop now ("" to keep going),
## from \a resources (FOUniverse.get_empire_resources(): planets) and this
## turn's \a sitreps (get_sitreps(): label). Remembers the planet count for
## the next turn.
func check(resources: Dictionary, sitreps: Array) -> String:
	var planets: int = resources.get("planets", -1)
	var reason := ""
	if _planets >= 0 and planets >= 0 and planets < _planets:
		reason = "AUTO_TURN_STOP_PLANET_LOST"
	_planets = planets
	for sitrep: Dictionary in sitreps:
		if reason == "":
			reason = SITREP_REASONS.get(sitrep.get("label", ""), "")
	return reason


## A new turn in \a shell: with automatic turn advance on, end it at once,
## or switch it off and say why when in danger.
func on_new_turn(shell: GameShell) -> void:
	var stop := check(FOUniverse.get_empire_resources(), FOUniverse.get_sitreps())
	if not shell.top_bar.auto_end_turn:
		return
	if stop == "":
		shell.top_bar.end_turn.call_deferred()
		return
	shell.top_bar.set_auto_end_turn(false)
	var note := TranslationServer.translate("AUTO_TURN_STOPPED").replace(
		"%1%", TranslationServer.translate(stop)
	)
	shell.message_log.toast.show_text(note)
	shell.chat_window.add_event(note)


## Forget the planet count (a new game, or a game loaded).
func reset() -> void:
	_planets = -1
