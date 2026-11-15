class_name CreditsScreen
extends PanelContainer
## About FreeOrion, as the GG About window and intro credits: the version,
## then tabs for the credits (people by group and third-party resources,
## from the content's credits.xml), the project's vision, its licence
## (COPYING), and the Godot Engine's licence and credits.

signal close_requested

## Tabs: label key.
const TABS := ["INTRO_BTN_CREDITS", "VISION", "LICENSE", "ABOUT_GODOT"]

## credits.xml to read; the content directory's by default.
var credits_path := ""
## COPYING to show; the content directory's by default.
var license_path := ""

var _version: Label
var _tabs: TabBar
var _list: VBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	# Names are shown as they are; never auto-translate them.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	var margin := MarginContainer.new()
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_version = ScreenKit.header(box, "ABOUT_WINDOW_TITLE", close_requested.emit)
	_tabs = TabBar.new()
	for key in TABS:
		_tabs.add_tab(tr(key))
	_tabs.tab_changed.connect(func(_tab): refresh())
	box.add_child(_tabs)
	_list = ScreenKit.list()
	_list.add_theme_constant_override("separation", FOUi.tokens.space_1)
	_scroll = ScreenKit.scrolling(_list)
	box.add_child(_scroll)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


## Show tab \a tab (an index into TABS).
func show_tab(tab: int) -> void:
	_tabs.current_tab = tab
	refresh()


func refresh() -> void:
	ScreenKit.clear(_list)
	_scroll.scroll_vertical = 0
	var game := is_instance_valid(get_node_or_null("/root/GlobalFreeOrionNode"))
	_version.text = "FreeOrion " + GlobalFreeOrionNode.get_version() if game else ""
	match TABS[_tabs.current_tab]:
		"INTRO_BTN_CREDITS":
			_fill_credits(_content_path(credits_path, "credits.xml"))
		"VISION":
			_add_text(tr("FREEORION_VISION"))
		"LICENSE":
			var path := _content_path(license_path, "COPYING")
			_add_text(FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "")
		"ABOUT_GODOT":
			_fill_godot()


func _content_path(path: String, file: String) -> String:
	if path.is_empty() and is_instance_valid(get_node_or_null("/root/GlobalFreeOrionNode")):
		return GlobalFreeOrionNode.get_resource_dir().path_join(file)
	return path


func _fill_credits(path: String) -> void:
	for group: Dictionary in read_credits(path):
		var title := ScreenKit.label(group["name"], "TitleLabel")
		_list.add_child(title)
		for line: String in group["lines"]:
			var label := ScreenKit.label(line)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_list.add_child(label)
		_list.add_child(HSeparator.new())


# The engine's own licence and its third-party components, as Godot asks
# projects to credit it.
func _fill_godot() -> void:
	var info := Engine.get_version_info()
	_list.add_child(ScreenKit.label("Godot Engine %s" % info.get("string", ""), "TitleLabel"))
	_add_text(Engine.get_license_text())
	_list.add_child(HSeparator.new())
	var components: Dictionary = Engine.get_copyright_info().reduce(
		func(acc, c): return acc.merged({c["name"]: c}), {}
	)
	for name: String in components:
		var lines: PackedStringArray = []
		for part: Dictionary in components[name]["parts"]:
			lines.push_back(
				"%s (%s)" % [", ".join(part.get("copyright", [])), part.get("license", "")]
			)
		var label := ScreenKit.label("%s — %s" % [name, "; ".join(lines)], "SmallLabel")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(label)


func _add_text(text: String) -> void:
	var label := ScreenKit.label(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(label)


## Groups of credits.xml at \a path: [{name, lines}], each line a person
## ("Name (nick) — task") or a resource ("Author — Title, licence, source").
static func read_credits(path: String) -> Array:
	var groups: Array = []
	if not FileAccess.file_exists(path):
		return groups
	var parser := XMLParser.new()
	if parser.open(path) != OK:
		return groups
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match parser.get_node_name():
			"GROUP":
				groups.push_back({"name": _attr(parser, "name"), "lines": PackedStringArray()})
			"PERSON":
				if not groups.is_empty():
					groups.back()["lines"].push_back(_person(parser))
			"RESOURCE":
				if not groups.is_empty():
					groups.back()["lines"].push_back(_resource(parser))
	return groups


static func _person(parser: XMLParser) -> String:
	var text := _attr(parser, "name")
	var nick := _attr(parser, "nick")
	if not nick.is_empty():
		text = ("%s (%s)" % [text, nick]) if not text.is_empty() else nick
	var task := _attr(parser, "task")
	return "%s — %s" % [text, task] if not task.is_empty() else text


static func _resource(parser: XMLParser) -> String:
	var parts: PackedStringArray = [_attr(parser, "title")]
	var license := _attr(parser, "license")
	if not license.is_empty():
		parts.push_back("%s %s" % [TranslationServer.translate("INTRO_CREDITS_LICENSE"), license])
	var source := _attr(parser, "source")
	if not source.is_empty():
		parts.push_back(source)
	return "%s — %s" % [_attr(parser, "author"), ", ".join(parts)]


static func _attr(parser: XMLParser, attribute: String) -> String:
	return parser.get_named_attribute_value_safe(attribute).strip_edges()
