class_name GalaxySetupScreen
extends PanelContainer
## New single-player game: player and empire, galaxy (seed, size, shape with
## a preview, age, frequencies) and AI opponents. Values are the setup.*
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
const SHAPE_PREVIEWS := {
	"SPIRAL_2": "gp_spiral2.png",
	"SPIRAL_3": "gp_spiral3.png",
	"SPIRAL_4": "gp_spiral4.png",
	"CLUSTER": "gp_cluster.png",
	"ELLIPTICAL": "gp_elliptical.png",
	"DISC": "gp_disc.png",
	"BOX": "gp_box.png",
	"IRREGULAR": "gp_irregular.png",
	"RING": "gp_ring.png",
	"RANDOM": "gp_random.png",
}

var source: Variant = OptionsSource.new()

var _editors := {}
var _preview: TextureRect
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


## Fill the form from the current setup options.
func refresh() -> void:
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
	return true


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
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", FOUi.tokens.space_6)
	form.add_child(grid)

	for field in TEXTS:
		var edit := LineEdit.new()
		edit.custom_minimum_size.x = 260
		_add_row(grid, field[1], edit, field[0])
		if field[0] == "setup.seed":
			edit.tooltip_text = tr("GSETUP_RANDOM_SEED")
	for field in NUMBERS:
		var spin := SpinBox.new()
		spin.min_value = field[2]
		spin.max_value = field[3]
		_add_row(grid, field[1], spin, field[0])
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
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(420, 310)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	side.add_child(_preview)
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
	_editors[option] = editor


func _update_preview() -> void:
	var shape: OptionButton = _editors["setup.galaxy.shape"]
	var key: String = shape.get_item_metadata(shape.selected) if shape.selected >= 0 else ""
	_preview.texture = FOArt.icon(SHAPE_PREVIEWS.get(key, ""))


func _on_start_pressed() -> void:
	if apply():
		start_requested.emit()


static func _levels(kind: String) -> Array:
	if kind == "none_to_high":
		return [["GALAXY_SETUP_NONE", "GSETUP_NONE"]] + LEVELS
	return LEVELS


static func _choice_index(choice: OptionButton, value: String) -> int:
	for i in choice.item_count:
		if choice.get_item_metadata(i) == value:
			return i
	return -1
