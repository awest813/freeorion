class_name MessageLog
extends Node
## Feeds the messages window what the GG client logs there: each turn
## begun, games saved, and wars, peace treaties and alliances between the
## player's empire and others; and opens the Pedia for "/pedia". Also, as
## the GG client: a server error stops ending turns automatically, and
## players' status changes refresh the empires' ready marks.

var _shell: GameShell
## Diplomatic status with each other empire, as last seen: id -> status.
var _statuses := {}


func _init(shell: GameShell) -> void:
	_shell = shell


func _ready() -> void:
	_shell.chat_window.pedia_requested.connect(open_pedia)
	if not _shell.follow_game:
		return
	var node := get_node_or_null("/root/GlobalFreeOrionNode")
	if node == null:
		return
	node.turn_update.connect(func(): turn_begun(node.get_current_turn()), CONNECT_DEFERRED)
	node.save_completed.connect(saved)
	node.diplomacy_changed.connect(func(): diplomacy(FODiplomacy.get_empires()))
	node.server_error.connect(func(_message, _fatal): _shell.top_bar.set_auto_end_turn(false))
	node.players_changed.connect(players_changed)
	# The server's saves arrived: an open save or load screen lists them.
	node.server_saves.connect(
		func():
			for screen: SaveLoadScreen in [_shell.save_screen, _shell.load_screen]:
				if screen.visible:
					screen.refresh()
	)
	diplomacy(FODiplomacy.get_empires())


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


## Messages for statuses in \a empires that differ from \a known (id ->
## status, updated): "A and B are now at war.", with the empires' colours.
static func diplomacy_changes(known: Dictionary, empires: Array) -> PackedStringArray:
	var messages := PackedStringArray()
	var own := {}
	for empire: Dictionary in empires:
		if empire.get("own", false):
			own = empire
	for empire: Dictionary in empires:
		var status: String = empire.get("status", "")
		if empire.get("own", false) or status.is_empty():
			continue
		var id: int = empire["id"]
		var before: String = known.get(id, "")
		known[id] = status
		if before.is_empty() or before == status:
			continue
		var key: String = (
			{
				"war": "MESSAGES_WAR_DECLARATION",
				"peace": "MESSAGES_PEACE_TREATY",
				"allied": "MESSAGES_ALLIANCE",
			}
			. get(status, "")
		)
		if key.is_empty():
			continue
		messages.push_back(
			TranslationServer.translate(key).replace("%1%", _named(own)).replace(
				"%2%", _named(empire)
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


static func _named(empire: Dictionary) -> String:
	var color: Color = empire.get("color", Color.WHITE)
	return "<rgba %d %d %d 255>%s</rgba>" % [color.r8, color.g8, color.b8, empire.get("name", "")]
