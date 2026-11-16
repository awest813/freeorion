class_name AutoTurnGuard
extends RefCounted
## Automatic turn advance stops itself when the empire is in danger, so a
## player away from the keys doesn't come back to a lost game: own planets
## lost, own ships destroyed, a battle or invasion the empire was in, a
## planet depopulated, an armed fleet of an empire at war (or of monsters)
## newly seen inside its supply range. check() says why, once per turn.

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
## Hostile armed fleets seen in supply range so far: id -> true.
var _hostile := {}


## The text key saying why auto end turn should stop now ("" to keep going),
## from \a resources (FOUniverse.get_empire_resources(): planets) and this
## turn's \a sitreps (get_sitreps(): label). Remembers the planet count for
## the next turn.
## \a hostile: ids of hostile_in_supply() now; one not seen in range before
## stops it.
func check(resources: Dictionary, sitreps: Array, hostile := []) -> String:
	var planets: int = resources.get("planets", -1)
	var first := _planets < 0
	var reason := ""
	if _planets >= 0 and planets >= 0 and planets < _planets:
		reason = "AUTO_TURN_STOP_PLANET_LOST"
	_planets = planets
	for sitrep: Dictionary in sitreps:
		if reason == "":
			reason = SITREP_REASONS.get(sitrep.get("label", ""), "")
	# Each hostile fleet stops it once, the first turn it is seen in range
	# (those there when the game is joined don't).
	for fleet_id: int in hostile:
		if reason == "" and not first and not _hostile.has(fleet_id):
			reason = "AUTO_TURN_STOP_ENEMY_SIGHTED"
		_hostile[fleet_id] = true
	return reason


## Ids of the armed fleets in \a fleets (FOObjects.list_objects("fleets"))
## seen now in one of \a supply (system id -> true) that belong to monsters
## or to an empire in \a at_war (empire id -> true).
static func hostile_in_supply(fleets: Array, supply: Dictionary, at_war: Dictionary) -> Array:
	var ids := []
	for fleet: Dictionary in fleets:
		var owner: int = fleet.get("owner_id", -1)
		if (
			fleet.get("armed", false)
			and fleet.get("visibility", "") == "visible"
			and supply.has(fleet.get("system_id", -1))
			and (owner < 0 or at_war.has(owner))
		):
			ids.push_back(fleet["id"])
	return ids


## A new turn in \a shell: with automatic turn advance on, end it at once,
## or switch it off and say why when in danger.
func on_new_turn(shell: GameShell) -> void:
	var stop := check(FOUniverse.get_empire_resources(), FOUniverse.get_sitreps(), _hostile_now())
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


## Forget the planet count and fleets seen (a new game, or a game loaded).
func reset() -> void:
	_planets = -1
	_hostile.clear()


# hostile_in_supply() for the running game.
static func _hostile_now() -> Array:
	var own := FOUniverse.get_empire_id()
	var snapshot: Dictionary = FOUniverse.get_map_snapshot()
	var system_ids: PackedInt32Array = snapshot.get("system_ids", PackedInt32Array())
	var owners: Array = Array(snapshot.get("supply_system_owners", []))
	var supply := {}
	var indices: Array = Array(snapshot.get("supply_systems", []))
	for k in mini(indices.size(), owners.size()):
		if owners[k] == own and indices[k] < system_ids.size():
			supply[system_ids[indices[k]]] = true
	var at_war := {}
	for empire: Dictionary in FODiplomacy.get_empires():
		if empire.get("status", "") == "war":
			at_war[empire["id"]] = true
	return hostile_in_supply(FOObjects.list_objects("fleets", false), supply, at_war)
