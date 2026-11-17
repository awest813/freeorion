class_name PediaScreen
extends PanelContainer
## The Pedia: search over all content on the left, the article on the right
## (icon, title, facts, rich-text description, prerequisites and unlocks),
## with back/forward history. Links to other articles open in place; links
## to map objects (planets, systems, fleets, ...) are emitted as
## link_activated for the shell.

signal close_requested
signal link_activated(kind: String, arg: String)

## Kinds that have articles (FOPedia); other link kinds go to the shell.
const ARTICLE_KINDS := [
	"tech",
	"buildingtype",
	"species",
	"special",
	"shippart",
	"shiphull",
	"fieldtype",
	"policy",
	"encyclopedia",
	"metertype",
	"empire",
	"shipdesign",
	"monsterdesign",
	"planet",
	"system",
	"fleet",
	"ship",
	"building",
]
## A picture for each kind of article, from the game's art (the start page
## and the topics list show them).
const KIND_ICONS := {
	"tech": "icons/buttons/research.png",
	"buildingtype": "icons/building/palace.png",
	"species": "icons/species/human.png",
	"special": "icons/specials_large/ancient_ruins.png",
	"shippart": "icons/ship_parts/zortrium_plating.png",
	"shiphull": "icons/ship_hulls/basic-medium-hull_small.png",
	"fieldtype": "fields/ion_storm.png",
	"policy": "icons/policies/social_propaganda.png",
	"encyclopedia": "icons/buttons/pedia.png",
	"metertype": "icons/meter/industry.png",
	"empire": "icons/buttons/empires.png",
	"shipdesign": "icons/buttons/design.png",
	"monsterdesign": "icons/monsters/kraken-3.png",
}
## Kinds of universe objects: their articles can show them on the map.
const OBJECT_KINDS := ["planet", "system", "fleet", "ship", "building"]
const MAX_RESULTS := 80
## Link lists longer than this say how many there are in their caption.
const COUNTED_LINKS := 3
## Start page tiles' size.
const TILE_WIDTH := 150
const TILE_HEIGHT := 112
## Groups of links under an article's facts, in this order.
const LINK_GROUPS := [
	"prerequisites",
	"leads_to",
	"unlocks",
	"unlocked_by",
	"exclusions",
	"hull",
	"parts",
	"likes",
	"dislikes",
	"liked_by",
	"disliked_by",
	"homeworlds",
	"policies",
	"planets",
]
const SIDEBAR_WIDTH := 320

var source: Variant = PediaSource.new()

var _history: Array = []
var _history_index := -1
var _index: Array = []
var _back: Button
var _forward: Button
var _title: Label
var _on_map: Button
## The shown article's universe object: [kind, id] or [].
var _object := []
var _icon: TextureRect
var _planet: PlanetView
var _facts: GridContainer
var _text: RichTextLabel
var _tiles: HFlowContainer
var _links: VBoxContainer
var _environments: HFlowContainer
var _search: LineEdit
var _results: VBoxContainer
var _browse_kind := ""


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()
	_show_article({})


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


## Whether links of \a kind open in the Pedia from anywhere (universe
## objects open on the map, and in the Pedia only from the Pedia).
static func is_article_kind(kind: String) -> bool:
	return kind in ARTICLE_KINDS and not kind in OBJECT_KINDS


## Open the article \a kind / \a article_name, adding it to the history.
func open(kind: String, article_name: String) -> bool:
	var article: Dictionary = source.get_article(kind, article_name)
	if article.is_empty():
		return false
	_history.resize(_history_index + 1)
	_history.push_back([kind, article_name])
	_history_index = _history.size() - 1
	_show_article(article)
	return true


func current() -> Array:
	return _history[_history_index] if _history_index >= 0 else []


func back() -> void:
	if _history_index > 0:
		_history_index -= 1
		_show_history_entry()


func forward() -> void:
	if _history_index < _history.size() - 1:
		_history_index += 1
		_show_history_entry()


func search(text: String) -> void:
	_search.text = text
	_refresh_results()


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", FOUi.tokens.space_6)
	margin.add_child(columns)

	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = SIDEBAR_WIDTH
	columns.add_child(sidebar)
	_search = LineEdit.new()
	_search.placeholder_text = tr("PEDIA_SEARCH")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_results())
	visibility_changed.connect(_on_visibility_changed)
	sidebar.add_child(_search)
	_results = ScreenKit.list()
	sidebar.add_child(ScreenKit.scrolling(_results))

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_back = ScreenKit.small_button("◀", "PEDIA_BACK", false)
	_back.pressed.connect(back)
	header.add_child(_back)
	_forward = ScreenKit.small_button("▶", "PEDIA_FORWARD", false)
	_forward.pressed.connect(forward)
	header.add_child(_forward)
	_title = ScreenKit.label("", "HeadingLabel")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_title)
	_on_map = Button.new()
	_on_map.text = tr("PEDIA_SHOW_ON_MAP")
	_on_map.theme_type_variation = "GhostButton"
	_on_map.visible = false
	_on_map.pressed.connect(func(): link_activated.emit(_object[0], _object[1]))
	header.add_child(_on_map)
	var close := ScreenKit.small_button("✕", "PANEL_CLOSE")
	close.pressed.connect(close_requested.emit)
	header.add_child(close)

	var summary := HBoxContainer.new()
	summary.add_theme_constant_override("separation", FOUi.tokens.space_4)
	content.add_child(summary)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2.ONE * FOUi.tokens.icon_large * 2
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	summary.add_child(_icon)
	# A planet's article shows the planet, as the map's panels do.
	_planet = PlanetView.new("", 0, FOUi.tokens.icon_large * 2)
	_planet.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_planet.visible = false
	summary.add_child(_planet)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(side)
	_facts = GridContainer.new()
	_facts.columns = 2
	side.add_child(_facts)
	_links = VBoxContainer.new()
	side.add_child(_links)
	_environments = HFlowContainer.new()
	_environments.add_theme_constant_override("h_separation", FOUi.tokens.space_3)
	side.add_child(_environments)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.selection_enabled = true
	_text.meta_clicked.connect(func(meta): _follow(FORichText.parse_link(str(meta))))
	content.add_child(_text)
	_tiles = HFlowContainer.new()
	_tiles.add_theme_constant_override("h_separation", FOUi.tokens.space_3)
	_tiles.add_theme_constant_override("v_separation", FOUi.tokens.space_3)
	_tiles.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tiles.visible = false
	content.add_child(_tiles)


func _show_history_entry() -> void:
	var entry: Array = _history[_history_index]
	_show_article(source.get_article(entry[0], entry[1]))


func _show_article(article: Dictionary) -> void:
	_back.disabled = _history_index <= 0
	_forward.disabled = _history_index >= _history.size() - 1
	_tiles.visible = article.is_empty()
	_text.fit_content = article.is_empty()
	_text.size_flags_vertical = (
		Control.SIZE_FILL if article.is_empty() else Control.SIZE_EXPAND_FILL
	)
	if article.is_empty():
		_title.text = tr("MAP_BTN_PEDIA")
		_icon.texture = null
		_icon.visible = false
		_planet.visible = false
		_text.text = tr("PEDIA_EMPTY")
		fill_start_tiles()
		ScreenKit.clear(_facts)
		ScreenKit.clear(_links)
		_fill_environments([])
		return
	_title.text = tr(article.get("title", ""))
	_object = (
		[article["kind"], str(article["name"])] if article.get("kind", "") in OBJECT_KINDS else []
	)
	_on_map.visible = not _object.is_empty()
	_icon.texture = FOArt.icon(article.get("icon", ""))
	# A species gets its painting where there is one.
	if article.get("kind", "") == "species":
		_icon.texture = EmpireArt.species_portrait(
			str(article.get("name", "")), article.get("icon", "")
		)
	_icon.visible = _icon.texture != null
	var planet_type: String = article.get("planet_type", "")
	_planet.visible = not planet_type.is_empty()
	if _planet.visible:
		_planet.show_planet(
			planet_type,
			int(str(article.get("name", "0"))),
			article.get("star_type", "STAR_YELLOW"),
			article.get("planet_size", "")
		)
	var text: String = article.get("text", "")
	var requirements: String = article.get("requirements", "")
	if not requirements.is_empty():
		text += "\n\n<b>%s</b>\n%s" % [tr("PEDIA_REQUIREMENTS"), requirements]
	_text.text = FORichText.to_bbcode(text, FOUi.tokens.icon_small)
	_text.scroll_to_line(0)
	ScreenKit.clear(_facts)
	for fact: Array in article.get("facts", []):
		_facts.add_child(ScreenKit.label(tr(fact[0]), "SecondaryLabel"))
		_facts.add_child(ScreenKit.label(str(fact[1])))
	ScreenKit.clear(_links)
	for group in LINK_GROUPS:
		var group_links: Array = article.get("links", []).filter(
			func(l): return l["group"] == group
		)
		if group_links.is_empty():
			continue
		# In the facts' grid, so names and values line up with the facts.
		var caption_text := tr("PEDIA_LINKS_" + group.to_upper())
		if group_links.size() > COUNTED_LINKS:  # how many, without counting them by eye
			caption_text += " (%d)" % group_links.size()
		var caption := ScreenKit.label(caption_text, "SecondaryLabel")
		# At the top of a long list of links, not halfway down it.
		caption.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_facts.add_child(caption)
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", FOUi.tokens.space_3)
		for link: Dictionary in group_links:
			var link_text: String = link.get("label", tr(link["name"]))
			if str(link.get("kind", "")).is_empty():
				row.add_child(ScreenKit.label(link_text))  # nothing to open
				continue
			var button := LinkButton.new()
			button.text = link_text
			button.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
			button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			button.pressed.connect(_follow.bind(link.duplicate().merged({"arg": link["name"]})))
			row.add_child(button)
		_facts.add_child(row)
	_fill_environments(article.get("environments", []))


## Colour of planet environment \a environment ("PE_GOOD", ...).
static func environment_color(environment: String) -> Color:
	var tokens := FOUi.tokens
	match environment:
		"PE_GOOD":
			return tokens.positive
		"PE_POOR":
			return tokens.warning
		"PE_HOSTILE":
			return tokens.negative
		"PE_UNINHABITABLE":
			return tokens.text_secondary
	return tokens.text_primary


# A species' environment on each planet type: icon, type, environment.
func _fill_environments(environments: Array) -> void:
	ScreenKit.clear(_environments)
	_environments.visible = not environments.is_empty()
	for entry: Dictionary in environments:
		var chip := HBoxContainer.new()
		var icon := ScreenKit.icon("", FOUi.tokens.icon_small)
		icon.texture = FOArt.planet_type_icon(entry.get("planet_type", ""))
		chip.add_child(icon)
		var environment: String = entry.get("environment", "")
		var label := ScreenKit.label(
			"%s: %s" % [tr(entry.get("planet_type", "")), tr(environment)], "SmallLabel"
		)
		label.add_theme_color_override("font_color", environment_color(environment))
		chip.add_child(label)
		_environments.add_child(chip)


func _follow(link: Dictionary) -> void:
	var kind: String = link.get("kind", "")
	var arg: String = link.get("arg", link.get("name", ""))
	if kind == "url":
		OS.shell_open(arg)
	elif is_article_kind(kind):
		open(kind, arg)
	elif kind in OBJECT_KINDS and open(kind, arg):
		pass
	else:
		link_activated.emit(kind, arg)


func _on_visibility_changed() -> void:
	if visible and _results.get_child_count() == 0:
		_refresh_results()
	# The start page was built before the game's content was read.
	if visible and _tiles.visible:
		fill_start_tiles()


## List every article of \a kind in the sidebar ("" lists the kinds).
func browse(kind: String) -> void:
	_search.text = ""
	_browse_kind = kind
	_refresh_results()


func _refresh_results() -> void:
	ScreenKit.clear(_results)
	if _index.is_empty():
		_index = source.get_index()
	var needle := _search.text.strip_edges().to_lower()
	if needle.is_empty() and _browse_kind.is_empty():
		_list_kinds()
		return
	var matches: Array = []
	for entry: Dictionary in _index:
		if needle.is_empty() and entry["kind"] != _browse_kind:
			continue
		var title: String = entry.get("label", tr(entry["name"]))
		if needle.is_empty() or title.to_lower().contains(needle):
			matches.push_back([title, entry])
	matches.sort_custom(func(a, b): return a[0].naturalnocasecmp_to(b[0]) < 0)
	_name_kinds_of_twins(matches)
	# Then articles whose text has it (GG's full-text search).
	if needle.length() >= 3:
		var found := {}
		for match: Array in matches:
			found[match[1]["kind"] + "/" + match[1]["name"]] = true
		for entry: Dictionary in source.search(needle):
			if not found.has(entry["kind"] + "/" + entry["name"]):
				matches.push_back(["%s  ·  %s" % [tr(entry["name"]), tr("PEDIA_IN_TEXT")], entry])
	if needle.is_empty():
		var up := _result_button("◀  " + tr("PEDIA_ALL_TOPICS"))
		up.pressed.connect(browse.bind(""))
		_results.add_child(up)
	var limit := MAX_RESULTS if not needle.is_empty() else matches.size()
	for match in matches.slice(0, limit):
		var button := _result_button(match[0])
		button.tooltip_text = tr("PEDIA_KIND_" + match[1]["kind"].to_upper())
		button.pressed.connect(open.bind(match[1]["kind"], match[1]["name"]))
		_results.add_child(button)
	if matches.is_empty():
		_results.add_child(ScreenKit.label(tr("PEDIA_NO_RESULTS"), "SecondaryLabel"))


# Results with the same title (a part and its article, "Armor Plating")
# say which kind each is, so the list doesn't show the same name twice.
static func _name_kinds_of_twins(matches: Array) -> void:
	var count := {}
	for entry: Array in matches:
		count[entry[0]] = count.get(entry[0], 0) + 1
	for entry: Array in matches:
		if count[entry[0]] > 1:
			var kind := TranslationServer.translate("PEDIA_KIND_" + entry[1]["kind"].to_upper())
			entry[0] = "%s  ·  %s" % [entry[0], kind]


# Browsing entry point: one button per kind with its article count.
func _list_kinds() -> void:
	var counts := {}
	for entry: Dictionary in _index:
		counts[entry["kind"]] = counts.get(entry["kind"], 0) + 1
	for kind in ARTICLE_KINDS:
		if not counts.has(kind):
			continue
		var button := _result_button(
			"%s  (%d)" % [tr("PEDIA_KIND_" + kind.to_upper()), counts[kind]]
		)
		button.icon = FOArt.icon(KIND_ICONS.get(kind, ""))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", FOUi.tokens.icon)
		button.pressed.connect(browse.bind(kind))
		_results.add_child(button)


## The start page: a tile for each kind of article, with its picture and
## how many there are; a tile lists that kind.
func fill_start_tiles() -> void:
	ScreenKit.clear(_tiles)
	# Not kept: the source can still change before the topics are listed.
	var index: Array = _index if not _index.is_empty() else source.get_index()
	var counts := {}
	for entry: Dictionary in index:
		counts[entry["kind"]] = counts.get(entry["kind"], 0) + 1
	for kind in ARTICLE_KINDS:
		if not counts.has(kind):
			continue
		var tile := Button.new()
		tile.text = "%s\n%d" % [tr("PEDIA_KIND_" + kind.to_upper()), counts[kind]]
		tile.icon = FOArt.icon(KIND_ICONS.get(kind, ""))
		tile.expand_icon = true
		tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		tile.custom_minimum_size = Vector2(TILE_WIDTH, TILE_HEIGHT)
		tile.add_theme_constant_override("icon_max_width", FOUi.tokens.icon_large)
		tile.pressed.connect(browse.bind(kind))
		_tiles.add_child(tile)


static func _result_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = "GhostButton"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return button
