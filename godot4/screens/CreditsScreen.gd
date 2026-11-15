class_name CreditsScreen
extends PanelContainer
## Credits: the people (by group) and the third-party resources, read from
## the content's credits.xml as the GG intro screen's credits are.

signal close_requested

## credits.xml to read; the content directory's by default.
var credits_path := ""


func _init() -> void:
	# Names are shown as they are; never auto-translate them.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	for child in get_children():
		child.queue_free()
	var margin := MarginContainer.new()
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	ScreenKit.header(box, "INTRO_BTN_CREDITS", close_requested.emit)
	var list := ScreenKit.list()
	list.add_theme_constant_override("separation", FOUi.tokens.space_1)
	box.add_child(ScreenKit.scrolling(list))
	var path := credits_path
	if path.is_empty() and is_instance_valid(GlobalFreeOrionNode):
		path = GlobalFreeOrionNode.get_resource_dir().path_join("credits.xml")
	for group: Dictionary in read_credits(path):
		var title := ScreenKit.label(group["name"], "TitleLabel")
		list.add_child(title)
		for line: String in group["lines"]:
			var label := ScreenKit.label(line)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(label)
		list.add_child(HSeparator.new())


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
