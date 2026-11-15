class_name MessageLog
extends Node
## Feeds the messages window what the GG client logs there: each turn
## begun, games saved, and wars, peace treaties and alliances between the
## player's empire and others; and opens the Pedia for "/pedia". Also, as
## the GG client: a server error stops ending turns automatically, and
## players' status changes refresh the empires' ready marks. A server
## error that doesn't end the game is logged with a toast (clicking it
## opens the messages); only fatal ones get a dialog.

## Statuses logged, and their message keys.
const DIPLOMACY_KEYS := {
	"war": "MESSAGES_WAR_DECLARATION",
	"peace": "MESSAGES_PEACE_TREATY",
	"allied": "MESSAGES_ALLIANCE",
}

## The note for errors that don't end the game.
var toast := Toast.new()

var _shell: GameShell
## Diplomatic status with each other empire, as last seen: id -> status.
var _statuses := {}


func _init(shell: GameShell) -> void:
	_shell = shell


func _ready() -> void:
	_shell.chat_window.pedia_requested.connect(open_pedia)
	_shell.chat_window.zoom_requested.connect(zoom_to)
	toast.pressed.connect(_shell.chat_window.open)
	_shell.add_child.call_deferred(toast)
	if not _shell.follow_game:
		return
	var node := get_node_or_null("/root/GlobalFreeOrionNode")
	if node == null:
		return
	node.turn_update.connect(func(): turn_begun(node.get_current_turn()), CONNECT_DEFERRED)
	node.save_completed.connect(saved)
	node.diplomacy_changed.connect(func(): diplomacy(FODiplomacy.get_empires()))
	node.server_error.connect(server_error)
	node.players_changed.connect(players_changed)
	# The server's saves arrived: an open save or load screen lists them.
	node.server_saves.connect(
		func():
			for screen: SaveLoadScreen in [_shell.save_screen, _shell.load_screen]:
				if screen.visible:
					screen.refresh()
	)
	diplomacy(FODiplomacy.get_empires())


## The server reported \a message: \a fatal ones (the game ends) in a
## dialog, others in the log and a toast, so several don't stack up.
func server_error(message: String, fatal: bool) -> void:
	_shell.top_bar.set_auto_end_turn(false)
	if fatal:
		FODialog.open_on(_shell, tr("SERVER_ERROR_TITLE"), message, [[tr("OK"), "PrimaryButton"]])
		return
	_shell.chat_window.add_event(tr("SERVER_ERROR_TITLE") + ": " + message)
	toast.show_text(message)


## Players' status changed (ready, playing): the empires list shows it.
func players_changed() -> void:
	if _shell.empires_screen.visible:
		_shell.empires_screen.refresh()


func turn_begun(turn: int) -> void:
	_shell.chat_window.add_event(tr("TURN_BEGIN").replace("%1%", str(turn)))


func saved(filename: String, bytes: int) -> void:
	_shell.chat_window.add_event(
		tr("SERVER_SAVE_COMPLETE").replace("%1%", filename.get_file()).replace("%2%", str(bytes))
	)


## Log the changes in \a empires' (FODiplomacy.get_empires()) statuses.
func diplomacy(empires: Array) -> void:
	for text in diplomacy_changes(_statuses, empires):
		_shell.chat_window.add_event(text)


## Messages for statuses in \a empires that differ from \a known (pair
## key -> status, updated): "A and B are now at war.", with the empires'
## colours; the player's empire first, and wars and treaties between other
## empires too (each empire's "statuses": other id -> status).
static func diplomacy_changes(known: Dictionary, empires: Array) -> PackedStringArray:
	var messages := PackedStringArray()
	var by_id := {}
	var own := {}
	for empire: Dictionary in empires:
		by_id[empire["id"]] = empire
		if empire.get("own", false):
			own = empire
	for empire: Dictionary in empires:
		var statuses: Dictionary = empire.get("statuses", {})
		if statuses.is_empty() and not own.is_empty() and not empire.get("own", false):
			statuses = {own["id"]: empire.get("status", "")}
		for other_id: int in statuses:
			var status: String = statuses[other_id]
			var first: Dictionary = empire
			var second: Dictionary = by_id.get(other_id, {})
			# Each pair once: the player's empire (else the lower id) first.
			if second.is_empty() or status.is_empty():
				continue
			if second.get("own", false) or (not first.get("own", false) and other_id < first["id"]):
				var swap := first
				first = second
				second = swap
			var pair := "%d:%d" % [first["id"], second["id"]]
			var before: String = known.get(pair, "")
			known[pair] = status
			var key: String = DIPLOMACY_KEYS.get(status, "")
			if before.is_empty() or before == status or key.is_empty():
				continue
			messages.push_back(
				TranslationServer.translate(key).replace("%1%", _named(first)).replace(
					"%2%", _named(second)
				)
			)
	return messages


## "/pedia [text]": the Pedia, searching for \a text (its topics if none).
func open_pedia(text: String) -> void:
	_shell.show_screen("pedia")
	if text.is_empty():
		_shell.pedia_screen.browse("")
	else:
		_shell.pedia_screen.search(text)


## "/zoom [name or id]": the system, planet or fleet it names on the map.
func zoom_to(text: String) -> void:
	var target := find_target(text) if _shell.follow_game else {}
	if target.is_empty():
		_shell.chat_window.add_event(tr("MESSAGES_ZOOM_NOT_FOUND").replace("%1%", text))
		return
	_shell.show_screen("")
	_shell.go_to(target)


## A GameShell.go_to() target for the object named \a text (or with that
## id): a system, a planet's system or a fleet; {} if none.
static func find_target(text: String) -> Dictionary:
	var needle := text.strip_edges().to_lower()
	if needle.is_empty():
		return {}
	var by_id := needle.is_valid_int()
	for system_id: int in FOUniverse.get_system_ids():
		var system: FOSystem = FOUniverse.get_system(system_id)
		if (
			system
			and (system.get_name().to_lower() == needle or by_id and int(needle) == system_id)
		):
			return {"system_id": system_id, "position": system.get_position()}
	for planet_id: int in FOUniverse.get_planet_ids():
		var planet: FOPlanet = FOUniverse.get_planet(planet_id)
		if (
			planet
			and (planet.get_name().to_lower() == needle or by_id and int(needle) == planet_id)
		):
			return {"system_id": planet.get_system_id()}
	for fleet_id: int in FOUniverse.get_fleet_ids():
		var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
		if fleet and (fleet.get_name().to_lower() == needle or by_id and int(needle) == fleet_id):
			return {
				"system_id": fleet.get_system_id(),
				"fleet_id": fleet_id,
				"position": fleet.get_position(),
			}
	return {}


static func _named(empire: Dictionary) -> String:
	var color: Color = empire.get("color", Color.WHITE)
	return "<rgba %d %d %d 255>%s</rgba>" % [color.r8, color.g8, color.b8, empire.get("name", "")]
