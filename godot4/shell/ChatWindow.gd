class_name ChatWindow
extends PanelContainer
## In-game messages (multiplayer): the chat with the other players, to
## everyone or whispered to one, in a window over the top left of the
## map. As the GG client's messages window; toggled from the top bar or
## with its hotkey. Counts what arrived while it was closed.

## Unread messages changed (for the top bar's badge).
signal unread_changed(count: int)

const EVERYONE := -1

var source: Variant = LobbySource.new()
var chat: ChatPanel
var recipient: OptionButton
var unread := 0

var _seen := 0


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
	box.add_child(chat)
	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(ScreenKit.label(tr("MP_CHAT_TO"), "SecondaryLabel"))
	recipient = OptionButton.new()
	recipient.fit_to_longest_item = false
	recipient.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(recipient)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	visible = true
	refresh()
	FOUi.fade_in(self)
	chat.input.grab_focus()


func close() -> void:
	visible = false
	if chat.input.has_focus():
		chat.input.release_focus()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Show the chat so far; while closed, count what's new.
func refresh() -> void:
	var lines: Array = source.chat()
	chat.set_lines(lines)
	if visible:
		_seen = lines.size()
	unread = maxi(0, lines.size() - _seen)
	unread_changed.emit(unread)
	_fill_recipients()


## Count everything so far as read (the lobby's chat when the game starts).
func mark_read() -> void:
	_seen = source.chat().size()
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
	var to: int = recipient.get_item_metadata(recipient.selected) if recipient.selected >= 0 else -1
	source.send_chat(text, PackedInt32Array() if to == EVERYONE else PackedInt32Array([to]))
