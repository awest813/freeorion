class_name NotificationFeed
extends PanelContainer
## A turn's situation reports as a collapsible list of rich-text entries;
## ‹ and › step back through earlier turns. Links (planets, systems, fleets,
## techs, ...) emit link_activated.
## Follows the running game unless follow_game is false; show_entries() then
## drives it directly (tests, previews).

signal link_activated(kind: String, arg: String)

const WIDTH := 380
const MAX_HEIGHT := 320

var follow_game := true
## turn -> its entries, for stepping through history; the game by default.
var entries_provider := func(turn: int) -> Array: return FOUniverse.get_sitreps(turn)

var _header: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _entries: Array = []
var _turn := 0
var _latest_turn := 0
var _prev: Button
var _next: Button


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "OverlayPanel"
	custom_minimum_size.x = WIDTH
	visible = false
	_build()


func _ready() -> void:
	if not follow_game or not is_instance_valid(GlobalFreeOrionNode):
		return
	GlobalFreeOrionNode.start_game.connect(_refresh_from_game.unbind(1))
	GlobalFreeOrionNode.turn_update.connect(_refresh_from_game)
	if GlobalFreeOrionNode.get_current_turn() >= 1:
		_refresh_from_game()


## Show \a entries ({text, icon, label}) for the latest turn \a turn;
## hidden when empty.
func show_entries(entries: Array, turn: int) -> void:
	_latest_turn = turn
	_show(entries, turn)


## Show the reports of earlier turn \a turn (clamped to 1..latest).
func show_turn(turn: int) -> void:
	turn = clampi(turn, 1, maxi(1, _latest_turn))
	_show(entries_provider.call(turn), turn)


func _show(entries: Array, turn: int) -> void:
	var was_visible := visible
	_entries = entries
	_turn = turn
	# Browsing history keeps the feed even on a quiet turn.
	visible = not entries.is_empty() or turn != _latest_turn
	for child in _list.get_children():
		child.queue_free()
	for entry: Dictionary in entries:
		_list.add_child(_entry_row(entry))
	_update_header()
	if visible and not was_visible:
		FOUi.fade_in(self)


func is_expanded() -> bool:
	return _scroll.visible


func set_expanded(expanded: bool) -> void:
	_scroll.visible = expanded
	_update_header()


func _refresh_from_game() -> void:
	show_entries(FOUniverse.get_sitreps(), GlobalFreeOrionNode.get_current_turn())


func _build() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var header_row := HBoxContainer.new()
	box.add_child(header_row)
	_header = Button.new()
	_header.theme_type_variation = "GhostButton"
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.pressed.connect(func(): set_expanded(not is_expanded()))
	header_row.add_child(_header)
	_prev = ScreenKit.small_button("‹", "NOTIFICATIONS_PREVIOUS_TURN")
	_prev.pressed.connect(func(): show_turn(_turn - 1))
	header_row.add_child(_prev)
	_next = ScreenKit.small_button("›", "NOTIFICATIONS_NEXT_TURN")
	_next.pressed.connect(func(): show_turn(_turn + 1))
	header_row.add_child(_next)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size.y = 0
	box.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_list.resized.connect(_fit_height)


func _entry_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = FOArt.icon(entry.get("icon", ""))
	icon.custom_minimum_size = Vector2(FOUi.tokens.icon, FOUi.tokens.icon)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = FORichText.to_bbcode(entry.get("text", ""), FOUi.tokens.icon_small)
	text.meta_clicked.connect(_on_meta_clicked)
	row.add_child(text)
	return row


func _on_meta_clicked(meta: Variant) -> void:
	var link := FORichText.parse_link(str(meta))
	if link["kind"] == "url":
		OS.shell_open(link["arg"])
		return
	link_activated.emit(link["kind"], link["arg"])


# Grow with the content up to MAX_HEIGHT, then scroll.
func _fit_height() -> void:
	_scroll.custom_minimum_size.y = minf(_list.size.y, MAX_HEIGHT)


func _update_header() -> void:
	var arrow := "▾" if is_expanded() else "▸"
	var key := "NOTIFICATIONS_HEADER_ONE" if _entries.size() == 1 else "NOTIFICATIONS_HEADER"
	var title := tr(key).replace("%1%", str(_turn)).replace("%2%", str(_entries.size()))
	_header.text = "%s  %s" % [arrow, title]
	_prev.disabled = _turn <= 1
	_next.disabled = _turn >= _latest_turn
