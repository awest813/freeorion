extends Node
## Keyboard shortcuts (autoload "FOHotkeys"): each is an input action
## ("fo_" + name) bound to one key with modifiers, from option
## "ui.hotkey.godot." + name ("Ctrl+H", "F2", or "" for none). The options
## screen rebinds them; changes apply at once.

signal changed

const ACTION_PREFIX := "fo_"
const OPTION_PREFIX := "ui.hotkey.godot."
## Shortcuts: name, label key, default. Esc (back, menu) stays fixed.
const HOTKEYS := [
	["screen_production", "HOTKEY_GODOT_PRODUCTION", "F2"],
	["screen_research", "HOTKEY_GODOT_RESEARCH", "F3"],
	["screen_government", "HOTKEY_GODOT_GOVERNMENT", "F4"],
	["screen_design", "HOTKEY_GODOT_DESIGN", "F6"],
	["screen_combat", "HOTKEY_GODOT_COMBAT", "F7"],
	["screen_objects", "HOTKEY_GODOT_OBJECTS", "F8"],
	["screen_empires", "HOTKEY_GODOT_EMPIRES", "F9"],
	["screen_pedia", "HOTKEY_GODOT_PEDIA", "F1"],
	["screen_save", "HOTKEY_GODOT_SAVE", "F5"],
	["screen_options", "HOTKEY_GODOT_OPTIONS", "F10"],
	["end_turn", "HOTKEY_MAP_END_TURN", "Ctrl+Enter"],
	["messages", "HOTKEY_MAP_MESSAGES", "Alt+T"],
	["fullscreen", "HOTKEY_FULLSCREEN", "Alt+Enter"],
	["sitrep", "HOTKEY_MAP_SIT_REP", "Ctrl+N"],
	["map_zoom_in", "HOTKEY_MAP_ZOOM_IN", "Equal"],
	["map_zoom_out", "HOTKEY_MAP_ZOOM_OUT", "Minus"],
	["map_pan_left", "HOTKEY_MAP_PAN_LEFT", "A"],
	["map_pan_right", "HOTKEY_MAP_PAN_RIGHT", "D"],
	["map_pan_up", "HOTKEY_MAP_PAN_UP", "W"],
	["map_pan_down", "HOTKEY_MAP_PAN_DOWN", "S"],
	["home", "HOTKEY_MAP_ZOOM_HOME_SYSTEM", "Ctrl+H"],
	["detection", "HOTKEY_GODOT_DETECTION", "Ctrl+D"],
	["scale_legend", "HOTKEY_MAP_TOGGLE_SCALE_LINE", "Ctrl+L"],
	["scale_circle", "HOTKEY_MAP_TOGGLE_SCALE_CIRCLE", "Alt+C"],
	["minimap", "HOTKEY_GODOT_MINIMAP", "Ctrl+M"],
	["map_mode", "HOTKEY_GODOT_MAP_MODE", "Ctrl+Tab"],
	["system_prev", "HOTKEY_MAP_ZOOM_PREV_SYSTEM", "Ctrl+Comma"],
	["system_next", "HOTKEY_MAP_ZOOM_NEXT_SYSTEM", "Ctrl+Period"],
	["owned_prev", "HOTKEY_MAP_ZOOM_PREV_OWNED_SYSTEM", "Shift+Ctrl+Comma"],
	["owned_next", "HOTKEY_MAP_ZOOM_NEXT_OWNED_SYSTEM", "Shift+Ctrl+Period"],
	["fleet_prev", "HOTKEY_MAP_ZOOM_PREV_FLEET", "Ctrl+F"],
	["fleet_next", "HOTKEY_MAP_ZOOM_NEXT_FLEET", "Ctrl+G"],
	["idle_prev", "HOTKEY_MAP_ZOOM_PREV_IDLE_FLEET", "Alt+F"],
	["idle_next", "HOTKEY_MAP_ZOOM_NEXT_IDLE_FLEET", "Alt+G"],
]

## Key names shown as the symbols on the key.
const KEY_SYMBOLS := {
	"Equal": "=",
	"Minus": "−",
	"Plus": "+",
	"Comma": ",",
	"Period": ".",
	"Slash": "/",
	"Backslash": "\\",
	"Semicolon": ";",
	"Apostrophe": "'",
	"BracketLeft": "[",
	"BracketRight": "]",
	"QuoteLeft": "`",
	"Up": "↑",
	"Down": "↓",
	"Left": "←",
	"Right": "→",
}

var _options: Object


func _ready() -> void:
	if Engine.has_singleton("FOOptions"):
		_options = Engine.get_singleton("FOOptions")
		for entry in HOTKEYS:
			_options.add_option(OPTION_PREFIX + entry[0], "HOTKEY_GODOT_OPTION", entry[2])
			_options.watch(OPTION_PREFIX + entry[0])
		_options.option_changed.connect(_on_option_changed)
	apply()


## (Re)bind every action from the options, or the defaults without them.
func apply() -> void:
	for entry in HOTKEYS:
		var action: String = ACTION_PREFIX + entry[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := parse(binding(entry[0]))
		if event:
			InputMap.action_add_event(action, event)
	changed.emit()


## The key text bound to \a hotkey ("Ctrl+H"; "" for none).
func binding(hotkey: String) -> String:
	if _options and _options.exists(OPTION_PREFIX + hotkey):
		return str(_options.get_value(OPTION_PREFIX + hotkey))
	return default_binding(hotkey)


## \a hotkey's binding as players read it ("Ctrl+=" for "Ctrl+Equal").
func shown(hotkey: String) -> String:
	return display(binding(hotkey))


## Binding \a text with its symbol keys as symbols ("Equal" -> "=").
static func display(text: String) -> String:
	var parts := text.split("+")
	for i in parts.size():
		parts[i] = KEY_SYMBOLS.get(parts[i], parts[i])
	return "+".join(parts)


static func default_binding(hotkey: String) -> String:
	for entry in HOTKEYS:
		if entry[0] == hotkey:
			return entry[2]
	return ""


## Bind \a hotkey to \a text ("" clears it); saved with the options.
func bind_key(hotkey: String, text: String) -> void:
	if _options and _options.exists(OPTION_PREFIX + hotkey):
		_options.set_value(OPTION_PREFIX + hotkey, text)
	apply()


## The hotkey \a event presses, or "" (modifiers must match exactly).
func match_event(event: InputEvent) -> String:
	if not event is InputEventKey or not event.pressed or event.echo:
		return ""
	for entry in HOTKEYS:
		if event.is_action_pressed(ACTION_PREFIX + entry[0], false, true):
			return entry[0]
	return ""


## Shortcut for a button, following the hotkey's binding.
static func shortcut(hotkey: String) -> Shortcut:
	var action := InputEventAction.new()
	action.action = ACTION_PREFIX + hotkey
	action.pressed = true
	var result := Shortcut.new()
	result.events = [action]
	return result


## Key event for \a text ("Shift+Ctrl+Comma"), or null if it names no key.
static func parse(text: String) -> InputEventKey:
	if text.strip_edges().is_empty():
		return null
	var event := InputEventKey.new()
	var parts := text.split("+")
	for i in parts.size() - 1:
		match parts[i].strip_edges().to_lower():
			"ctrl":
				event.ctrl_pressed = true
			"shift":
				event.shift_pressed = true
			"alt":
				event.alt_pressed = true
			"meta", "command", "cmd":
				event.meta_pressed = true
			_:
				return null
	event.keycode = OS.find_keycode_from_string(parts[-1].strip_edges())
	return event if event.keycode != KEY_NONE else null


## Text for key \a event with its modifiers ("Shift+Ctrl+Comma"), or "" for
## a lone modifier.
static func describe(event: InputEventKey) -> String:
	if event.keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_NONE]:
		return ""
	var parts: PackedStringArray = []
	if event.shift_pressed:
		parts.push_back("Shift")
	if event.ctrl_pressed:
		parts.push_back("Ctrl")
	if event.alt_pressed:
		parts.push_back("Alt")
	if event.meta_pressed:
		parts.push_back("Meta")
	parts.push_back(OS.get_keycode_string(event.keycode))
	return "+".join(parts)


## Hotkeys other than \a hotkey bound to \a text.
func conflicts(hotkey: String, text: String) -> Array:
	var others := []
	if text.is_empty():
		return others
	var wanted := normalized(text)
	for entry in HOTKEYS:
		if entry[0] != hotkey and normalized(binding(entry[0])) == wanted:
			others.push_back(entry[0])
	return others


## \a text in the form describe() gives, so equal keys compare equal.
static func normalized(text: String) -> String:
	var event := parse(text)
	return describe(event) if event else ""


func _on_option_changed(option: String) -> void:
	if option.begins_with(OPTION_PREFIX):
		apply()
