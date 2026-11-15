class_name ChatWindow
extends PanelContainer
## In-game messages: the chat with the other players, to everyone or
## whispered to one, and what happened to the game (turns begun, games
## saved, wars and treaties), in a window over the top left of the map. As
## the GG client's messages window, with its commands: /pedia [article],
## /pm [player] [message], /zoom [object], /help. Toggled from the top bar or with its
## hotkey; counts what arrived while it was closed.

## Unread messages changed (for the top bar's badge).
signal unread_changed(count: int)
## "/pedia text": open the Pedia at what \a text names (or its index).
signal pedia_requested(text: String)
## "/zoom text": show the system, planet or fleet \a text names on the map.
signal zoom_requested(text: String)

const EVERYONE := -1
const COMMANDS := ["/help", "/pedia", "/pm", "/zoom"]
const OPTION_TIMESTAMPS := "ui.map.messages.timestamp.shown"

var source: Variant = LobbySource.new()
var chat: ChatPanel
var recipient: OptionButton
var unread := 0
## The game's own messages: [{text, after (chat lines before it)}].
var events: Array = []

var _seen := 0
var _times: CheckBox


func _init() -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "OverlayPanel"
	visible = false
	custom_minimum_size = Vector2(420, 260)
	var box := VBoxContainer.new()
	add_child(box)
	ScreenKit.header(box, "MESSAGES_PANEL_TITLE", close)
	chat = ChatPanel.new()
	chat.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat.message_sent.connect(_send)
	chat.completions = completions
	box.add_child(chat)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(ScreenKit.label(tr("MP_CHAT_TO"), "SecondaryLabel"))
	recipient = OptionButton.new()
	recipient.fit_to_longest_item = false
	recipient.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(recipient)
	# Times before the lines, or not (kept in the options).
	var times := CheckBox.new()
	times.text = "⏱"
	times.tooltip_text = tr("OPTIONS_DB_DISPLAY_TIMESTAMP")
	times.button_pressed = chat.show_time
	times.toggled.connect(set_show_time)
	row.add_child(times)
	_times = times


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	var options := _options()
	if options and options.exists(OPTION_TIMESTAMPS):
		chat.show_time = options.get_value(OPTION_TIMESTAMPS)
		_times.set_pressed_no_signal(chat.show_time)
	refresh()
	FOUi.fade_in(self)
	chat.input.grab_focus()


## Show the time each line was sent, or not.
func set_show_time(shown: bool) -> void:
	chat.show_time = shown
	var options := _options()
	if options and options.exists(OPTION_TIMESTAMPS):
		options.set_value(OPTION_TIMESTAMPS, shown)
		options.commit()
	refresh()


static func _options() -> Object:
	return Engine.get_singleton("FOOptions") if Engine.has_singleton("FOOptions") else null


func close() -> void:
	visible = false
	if chat.input.has_focus():
		chat.input.release_focus()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Note \a text (FreeOrion markup allowed) in the log, after the chat so far.
func add_event(text: String) -> void:
	events.push_back({"text": text, "after": source.chat().size()})
	refresh()


## Chat \a lines with the events interleaved where they happened.
func merged(lines: Array) -> Array:
	var result := []
	var event_index := 0
	for i in lines.size() + 1:
		while event_index < events.size() and events[event_index]["after"] <= i:
			result.push_back({"text": events[event_index]["text"], "event": true})
			event_index += 1
		if i < lines.size():
			result.push_back(lines[i])
	return result


## Show the chat so far; while closed, count what's new.
func refresh() -> void:
	var lines: Array = merged(source.chat())
	chat.set_lines(lines)
	if visible:
		_seen = lines.size()
	unread = maxi(0, lines.size() - _seen)
	unread_changed.emit(unread)
	_fill_recipients()


## Count everything so far as read (the lobby's chat when the game starts).
func mark_read() -> void:
	_seen = merged(source.chat()).size()
	unread = 0
	unread_changed.emit(unread)


func _fill_recipients() -> void:
	var picked: int = (
		recipient.get_item_metadata(recipient.selected) if recipient.selected >= 0 else EVERYONE
	)
	recipient.clear()
	recipient.add_item(tr("MP_CHAT_EVERYONE"))
	recipient.set_item_metadata(0, EVERYONE)
	for player: Dictionary in source.players():
		var player_id: int = player.get("player_id", -1)
		if player_id == source.player_id() or player.get("client_type", "") == "ai":
			continue
		recipient.add_item(player.get("name", ""))
		recipient.set_item_metadata(recipient.item_count - 1, player_id)
		if player_id == picked:
			recipient.select(recipient.item_count - 1)


func _send(text: String) -> void:
	if text.begins_with("/"):
		run_command(text)
		return
	var to: int = recipient.get_item_metadata(recipient.selected) if recipient.selected >= 0 else -1
	source.send_chat(text, PackedInt32Array() if to == EVERYONE else PackedInt32Array([to]))


## Do chat command \a text (GG's MessageWnd commands).
func run_command(text: String) -> void:
	var space := text.find(" ")
	var command := text.substr(1, space - 1 if space > 0 else -1).to_lower()
	var params := text.substr(space + 1).strip_edges() if space > 0 else ""
	match command:
		"pedia":
			pedia_requested.emit(params)
		"zoom":
			zoom_requested.emit(params)
		"pm":
			var target := _player_named(params)
			var message := params.substr(str(target.get("name", "")).length()).strip_edges()
			if target.is_empty() or message.is_empty():
				add_event(tr("MESSAGES_INVALID"))
			else:
				source.send_chat(message, PackedInt32Array([target["player_id"]]))
		_:
			add_event(tr("MESSAGES_HELP_COMMAND"))


## What Tab completes: the commands and the players' names.
func completions() -> PackedStringArray:
	var words := PackedStringArray(COMMANDS)
	for player: Dictionary in source.players():
		if not str(player.get("name", "")).is_empty():
			words.push_back(player["name"])
	return words


# The player whose name \a text starts with (the longest such name).
func _player_named(text: String) -> Dictionary:
	var found := {}
	for player: Dictionary in source.players():
		var player_name: String = player.get("name", "")
		if (
			not player_name.is_empty()
			and text.begins_with(player_name)
			and player_name.length() > str(found.get("name", "")).length()
		):
			found = player
	return found
