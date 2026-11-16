class_name GalaxySetupScreen
extends PanelContainer
## New single-player game: player, empire (name, species, colour), galaxy
## (seed, size, shape with a preview, age, frequencies) and AI opponents;
## and on a second tab the game rules, generated from their metadata. Values are the setup.*
## options that the bridge's new_single_player_game() reads, so the form
## reads them on show and writes them back on Start.

signal back_requested
signal start_requested

## Choice fields: option, label key, [option value, label key] pairs.
const CHOICES := [
	[
		"setup.galaxy.shape",
		"GSETUP_SHAPE",
		[
			["SPIRAL_2", "GSETUP_2ARM"],
			["SPIRAL_3", "GSETUP_3ARM"],
			["SPIRAL_4", "GSETUP_4ARM"],
			["CLUSTER", "GSETUP_CLUSTER"],
			["ELLIPTICAL", "GSETUP_ELLIPTICAL"],
			["DISC", "GSETUP_DISC"],
			["BOX", "GSETUP_BOX"],
			["IRREGULAR", "GSETUP_IRREGULAR"],
			["RING", "GSETUP_RING"],
			["RANDOM", "GSETUP_RANDOM"],
		],
	],
	[
		"setup.galaxy.age",
		"GSETUP_AGE",
		[
			["GALAXY_SETUP_LOW", "GSETUP_YOUNG"],
			["GALAXY_SETUP_MEDIUM", "GSETUP_MATURE"],
			["GALAXY_SETUP_HIGH", "GSETUP_ANCIENT"],
			["GALAXY_SETUP_RANDOM", "GSETUP_RANDOM"],
		],
	],
	["setup.starlane.frequency", "GSETUP_STARLANE_FREQ", "low_to_high"],
	["setup.planet.density", "GSETUP_PLANET_DENSITY", "low_to_high"],
	["setup.specials.frequency", "GSETUP_SPECIALS_FREQ", "none_to_high"],
	["setup.native.frequency", "GSETUP_NATIVE_FREQ", "none_to_high"],
	[
		"setup.monster.frequency",
		"GSETUP_MONSTER_FREQ",
		[
			["MONSTER_SETUP_NONE", "GSETUP_NONE"],
			["MONSTER_SETUP_EXTREMELY_LOW", "GSETUP_EXTREMELY_LOW"],
			["MONSTER_SETUP_VERY_LOW", "GSETUP_VERY_LOW"],
			["MONSTER_SETUP_LOW", "GSETUP_LOW"],
			["MONSTER_SETUP_MEDIUM", "GSETUP_MEDIUM"],
			["MONSTER_SETUP_HIGH", "GSETUP_HIGH"],
			["MONSTER_SETUP_VERY_HIGH", "GSETUP_VERY_HIGH"],
			["MONSTER_SETUP_EXTREMELY_HIGH", "GSETUP_EXTREMELY_HIGH"],
			["MONSTER_SETUP_RANDOM", "GSETUP_RANDOM"],
		],
	],
	[
		"setup.ai.aggression",
		"GSETUP_AI_AGGR",
		[
			["BEGINNER", "GSETUP_BEGINNER"],
			["TURTLE", "GSETUP_TURTLE"],
			["CAUTIOUS", "GSETUP_CAUTIOUS"],
			["TYPICAL", "GSETUP_TYPICAL"],
			["AGGRESSIVE", "GSETUP_AGGRESSIVE"],
			["MANIACAL", "GSETUP_MANIACAL"],
		],
	],
]
const LEVELS := [
	["GALAXY_SETUP_LOW", "GSETUP_LOW"],
	["GALAXY_SETUP_MEDIUM", "GSETUP_MEDIUM"],
	["GALAXY_SETUP_HIGH", "GSETUP_HIGH"],
	["GALAXY_SETUP_RANDOM", "GSETUP_RANDOM"],
]
## Number fields: option, label key, min, max.
const NUMBERS := [
	["setup.star.count", "GSETUP_STARS", 10, 5000],
	["setup.ai.player.count", "GSETUP_NUMBER_AIS", 0, 40],
]
## Text fields: option, label key.
const TEXTS := [
	["setup.player.name", "GSETUP_PLAYER_NAME"],
	["setup.empire.name", "GSETUP_EMPIRE_NAME"],
	["setup.seed", "GSETUP_SEED"],
]

var source: Variant = OptionsSource.new()

var _editors := {}
var _species: OptionButton
var _colors: HFlowContainer
var _color_index := 0
var _pages: Array[Control] = []
var _rule_tabs: TabBar
var _rule_list: VBoxContainer
var _rules: Array = []
## Rule values as edited: {name: value}.
var _rule_values := {}
var _preview: GalaxyPreview
## Who the player will be: flag, empire name, species portrait.
var _flag: TextureRect
var _identity: Label
var _portrait: TextureRect
var _status: Label


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


## Fill the form from the current setup options and game rules.
func refresh() -> void:
	_fill_species()
	_fill_colors()
	_load_rules()
	for option in _editors:
		var editor: Control = _editors[option]
		var value: Variant = source.get_value(option) if source.exists(option) else null
		if value == null:
			continue
		if editor is OptionButton:
			var index := _choice_index(editor, str(value))
			if index >= 0:
				editor.select(index)
		elif editor is SpinBox:
			editor.set_value_no_signal(value)
		elif editor is LineEdit:
			editor.text = str(value)
	if source.exists("setup.empire.color.index"):
		_select_color(int(source.get_value("setup.empire.color.index")))
	_status.text = ""
	_update_preview()


## Write the form to the setup options; false (with a message) if one is refused.
func apply() -> bool:
	for option in _editors:
		var editor: Control = _editors[option]
		var value: Variant
		if editor is OptionButton:
			value = editor.get_item_metadata(editor.selected)
		elif editor is SpinBox:
			value = int(editor.value)
		else:
			value = editor.text.strip_edges()
		if source.exists(option) and not source.set_value(option, value):
			_status.text = tr("OPTIONS_INVALID").replace("%1%", option)
			return false
	if source.exists("setup.empire.color.index"):
		source.set_value("setup.empire.color.index", _color_index)
	if not source.set_game_rules(changed_rules()):
		_status.text = tr("OPTIONS_INVALID").replace("%1%", tr("GSETUP_TAB_RULES"))
		return false
	return true


## Rules set to something other than their default: {name: value}.
func changed_rules() -> Dictionary:
	var changed := {}
	for rule: Dictionary in _rules:
		var rule_name: String = rule["name"]
		if _rule_values.has(rule_name) and _rule_values[rule_name] != rule["default"]:
			changed[rule_name] = _rule_values[rule_name]
	return changed


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", FOUi.tokens.space_8)
	margin.add_child(columns)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(form)
	_status = ScreenKit.header(form, "GSETUP_WINDOW_TITLE", back_requested.emit)
	var page_tabs := TabBar.new()
	page_tabs.add_tab(tr("GSETUP_TAB_GALAXY"))
	page_tabs.add_tab(tr("GSETUP_TAB_RULES"))
	page_tabs.tab_changed.connect(_show_page)
	form.add_child(page_tabs)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", FOUi.tokens.space_6)
	form.add_child(grid)
	_pages.push_back(grid)
	var rules_page := VBoxContainer.new()
	rules_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rules_page.visible = false
	form.add_child(rules_page)
	_pages.push_back(rules_page)
	_rule_tabs = TabBar.new()
	_rule_tabs.clip_tabs = false
	_rule_tabs.tab_changed.connect(func(_t): _fill_rule_list())
	rules_page.add_child(_rule_tabs)
	_rule_list = ScreenKit.list()
	rules_page.add_child(ScreenKit.scrolling(_rule_list))

	for field in TEXTS:
		var edit := LineEdit.new()
		edit.custom_minimum_size.x = 260
		if field[0] == "setup.seed":
			# The seed, and a button rolling a new one.
			edit.tooltip_text = tr("GSETUP_SEED_TIP")
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var seed_row := HBoxContainer.new()
			seed_row.add_child(edit)
			var roll := ScreenKit.small_button("⚄", "GSETUP_RANDOMIZE_SEED")
			roll.pressed.connect(func(): edit.text = random_seed())
			seed_row.add_child(roll)
			_add_row(grid, field[1], seed_row, "")
			_editors[field[0]] = edit
			continue
		_add_row(grid, field[1], edit, field[0])
		if field[0] == "setup.empire.name":
			edit.text_changed.connect(func(_t): _update_identity())
			_species = OptionButton.new()
			_species.item_selected.connect(func(_i): _update_identity())
			_species.tooltip_text = tr("GSETUP_SPECIES_RANDOM_DESC")
			_add_row(grid, "GSETUP_SPECIES", _species, "setup.initial.species")
			_colors = HFlowContainer.new()
			_colors.add_theme_constant_override("h_separation", FOUi.tokens.space_1)
			_colors.add_theme_constant_override("v_separation", FOUi.tokens.space_1)
			_add_row(grid, "GSETUP_EMPIRE_COLOR", _colors, "")
	for field in NUMBERS:
		var spin := SpinBox.new()
		spin.min_value = field[2]
		spin.max_value = field[3]
		_add_row(grid, field[1], spin, field[0])
		if field[0] == "setup.star.count":
			spin.value_changed.connect(func(v: float): _preview.systems = int(v))
	for field in CHOICES:
		var choice := OptionButton.new()
		var values: Array = field[2] if field[2] is Array else _levels(field[2])
		for value in values:
			choice.add_item(tr(value[1]))
			choice.set_item_metadata(choice.item_count - 1, value[0])
		if field[0] == "setup.galaxy.shape":
			choice.item_selected.connect(func(_i): _update_preview())
		_add_row(grid, field[1], choice, field[0])

	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 420
	columns.add_child(side)
	_preview = GalaxyPreview.new()
	_preview.custom_minimum_size = Vector2(420, 310)
	side.add_child(_preview)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", FOUi.tokens.space_3)
	side.add_child(who)
	_portrait = ScreenKit.icon("", FOUi.tokens.icon_large * 2)
	who.add_child(_portrait)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_child(names)
	_flag = ScreenKit.icon("", FOUi.tokens.icon_large)
	names.add_child(_flag)
	_identity = ScreenKit.label("", "TitleLabel")
	_identity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(_identity)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	side.add_child(buttons)
	var back := Button.new()
	back.text = tr("TITLE_BACK")
	back.theme_type_variation = "GhostButton"
	back.pressed.connect(back_requested.emit)
	buttons.add_child(back)
	var start := Button.new()
	start.text = tr("TITLE_START_GAME")
	start.theme_type_variation = "PrimaryButton"
	start.pressed.connect(_on_start_pressed)
	buttons.add_child(start)


func _add_row(grid: GridContainer, label_key: String, editor: Control, option: String) -> void:
	grid.add_child(ScreenKit.label(tr(label_key), "SecondaryLabel"))
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(editor)
	if not option.is_empty():
		_editors[option] = editor


func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index


# Rules and their categories ("" is General), keeping edits already made.
func _load_rules() -> void:
	_rules = source.game_rules()
	for rule: Dictionary in _rules:
		if not _rule_values.has(rule["name"]):
			_rule_values[rule["name"]] = rule["value"]
	var categories: Array = []
	for rule: Dictionary in _rules:
		if not categories.has(rule["category"]):
			categories.push_back(rule["category"])
	var current := _rule_tabs.current_tab
	while _rule_tabs.tab_count > 0:
		_rule_tabs.remove_tab(0)
	for category: String in categories:
		_rule_tabs.add_tab(tr(category if not category.is_empty() else "GENERAL"))
		_rule_tabs.set_tab_metadata(_rule_tabs.tab_count - 1, category)
	if _rule_tabs.tab_count > 0:
		_rule_tabs.current_tab = clampi(current, 0, _rule_tabs.tab_count - 1)
	_fill_rule_list()


func _fill_rule_list() -> void:
	ScreenKit.clear(_rule_list)
	if _rule_tabs.tab_count == 0:
		return
	# Adding the first tab switches to it before its category is set.
	var category: Variant = _rule_tabs.get_tab_metadata(_rule_tabs.current_tab)
	if category == null:
		return
	for rule: Dictionary in _rules:
		if rule["category"] == category:
			_rule_list.add_child(_rule_row(rule))


# A rule: its name (description in the tooltip), an editor for its type,
# and a reset button while it differs from the default.
func _rule_row(rule: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var rule_name: String = rule["name"]
	var label := ScreenKit.label(tr(rule_name))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	if not str(rule.get("description", "")).is_empty():
		label.tooltip_text = tr(rule["description"])
	row.add_child(label)
	var value: Variant = _rule_values.get(rule_name, rule["value"])
	var editor: Control
	match rule["type"]:
		"toggle":
			var check := CheckBox.new()
			check.button_pressed = value
			check.toggled.connect(_set_rule.bind(rule_name))
			editor = check
		"int", "double":
			var spin := SpinBox.new()
			var is_int: bool = rule["type"] == "int"
			spin.step = rule.get("step", 1 if is_int else 0.01)
			spin.min_value = rule.get("min", -1000000)
			spin.max_value = rule.get("max", 1000000)
			spin.value = value
			spin.custom_minimum_size.x = 140
			spin.value_changed.connect(
				func(v: float): _set_rule(int(v) if is_int else v, rule_name)
			)
			editor = spin
		_:
			if rule.has("choices"):
				var choice := OptionButton.new()
				for option: String in rule["choices"]:
					choice.add_item(tr(option))
					choice.set_item_metadata(choice.item_count - 1, option)
					if option == value:
						choice.select(choice.item_count - 1)
				choice.item_selected.connect(
					func(i: int): _set_rule(choice.get_item_metadata(i), rule_name)
				)
				editor = choice
			else:
				var edit := LineEdit.new()
				edit.text = str(value)
				edit.custom_minimum_size.x = 180
				edit.text_changed.connect(_set_rule.bind(rule_name))
				editor = edit
	editor.tooltip_text = label.tooltip_text
	row.add_child(editor)
	var reset := ScreenKit.small_button("↺", "GSETUP_RULE_RESET")
	reset.pressed.connect(_reset_rule.bind(rule_name))
	row.add_child(reset)
	_show_reset(reset, value != rule["default"])
	return row


# The reset button keeps its place when hidden, so editors stay aligned.
static func _show_reset(reset: Button, shown: bool) -> void:
	reset.disabled = not shown
	reset.modulate.a = 1.0 if shown else 0.0
	reset.mouse_filter = Control.MOUSE_FILTER_STOP if shown else Control.MOUSE_FILTER_IGNORE


func _set_rule(value: Variant, rule_name: String) -> void:
	_rule_values[rule_name] = value
	# Show or hide the reset button of that rule's row.
	for rule: Dictionary in _rules:
		if rule["name"] == rule_name:
			for row in _rule_list.get_children():
				if row.get_child(0).text == tr(rule_name):
					_show_reset(row.get_child(2), value != rule["default"])


func _reset_rule(rule_name: String) -> void:
	for rule: Dictionary in _rules:
		if rule["name"] == rule_name:
			_rule_values[rule_name] = rule["default"]
	_fill_rule_list()


# Species to start with, and "Random". Content may still be parsing on the
# first refresh, so this refills each time.
func _fill_species() -> void:
	_species.clear()
	for species: Dictionary in source.playable_species():
		_species.add_item(tr(species["name"]))
		var index := _species.item_count - 1
		_species.set_item_metadata(index, species["name"])
		var icon := FOArt.icon(species.get("icon", ""))
		if icon:
			_species.set_item_icon(index, icon)
	_species.add_item(tr("GSETUP_RANDOM"))
	_species.set_item_metadata(_species.item_count - 1, "RANDOM")
	_species.add_theme_constant_override("icon_max_width", FOUi.tokens.icon)


# A swatch per empire colour; one is picked.
func _fill_colors() -> void:
	ScreenKit.clear(_colors)
	var group := ButtonGroup.new()
	var colors: PackedColorArray = source.empire_colors()
	for i in colors.size():
		var swatch := Button.new()
		swatch.toggle_mode = true
		swatch.button_group = group
		swatch.custom_minimum_size = Vector2.ONE * FOUi.tokens.icon
		swatch.tooltip_text = tr("GSETUP_EMPIRE_COLOR")
		var fill := StyleBoxFlat.new()
		fill.bg_color = colors[i]
		fill.set_corner_radius_all(FOUi.tokens.radius_small)
		var picked := fill.duplicate()
		picked.set_border_width_all(FOUi.tokens.focus_width)
		picked.border_color = FOUi.tokens.text_primary
		for state in ["normal", "hover", "disabled"]:
			swatch.add_theme_stylebox_override(state, fill)
		for state in ["pressed", "hover_pressed"]:
			swatch.add_theme_stylebox_override(state, picked)
		swatch.pressed.connect(_select_color.bind(i))
		_colors.add_child(swatch)


func _select_color(index: int) -> void:
	var swatches := _colors.get_children().filter(func(c): return not c.is_queued_for_deletion())
	_color_index = clampi(index, 0, maxi(0, swatches.size() - 1))
	for i in swatches.size():
		swatches[i].set_pressed_no_signal(i == _color_index)
	_update_identity()


func _update_preview() -> void:
	var shape: OptionButton = _editors["setup.galaxy.shape"]
	var key: String = shape.get_item_metadata(shape.selected) if shape.selected >= 0 else ""
	_preview.shape = key
	var stars: SpinBox = _editors.get("setup.star.count")
	if stars:
		_preview.systems = int(stars.value)
	_update_identity()


# The flag, name and people of the empire as set up so far.
func _update_identity() -> void:
	if _identity == null:
		return
	var name_edit: LineEdit = _editors.get("setup.empire.name")
	var empire_name := name_edit.text if name_edit else ""
	var colors: PackedColorArray = source.empire_colors() if source else PackedColorArray()
	var color := colors[_color_index] if _color_index < colors.size() else Color.WHITE
	_identity.text = empire_name
	_flag.texture = EmpireArt.flag(empire_name, color, FOUi.tokens.icon_large)
	var species: String = (
		_species.get_item_metadata(_species.selected) if _species and _species.selected >= 0 else ""
	)
	_portrait.texture = (
		EmpireArt.species_portrait(species) if species not in ["", "RANDOM"] else null
	)


func _on_start_pressed() -> void:
	if apply():
		start_requested.emit()


## A new random seed: eight letters and digits, as GG's randomise button.
static func random_seed() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var text := ""
	for i in 8:
		text += CHARS[randi() % CHARS.length()]
	return text


static func _levels(kind: String) -> Array:
	if kind == "none_to_high":
		return [["GALAXY_SETUP_NONE", "GSETUP_NONE"]] + LEVELS
	return LEVELS


static func _choice_index(choice: OptionButton, value: String) -> int:
	for i in choice.item_count:
		if choice.get_item_metadata(i) == value:
			return i
	return -1
