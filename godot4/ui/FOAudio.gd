extends Node
## Music and interface sounds (autoload "FOAudio"), from the audio.* options
## the GG client uses: music and effects on/off and volume (0-255). Every
## button clicks when pressed and ticks softly when hovered; a button can
## pick another sound with set_meta("sound", name) or none with "". As in the
## GG client, drop-downs have their own sound, choosing in a list and
## dropping a dragged item sound, side panels and screens sound as they open
## and close, and fleets and systems on the map as they're hovered and
## fleets as they're clicked. The new turn has its own sound. Nothing is
## heard until the Shell calls set_audible(), so tests and tools stay silent.

const OPTION_MUSIC := "audio.music.enabled"
const OPTION_MUSIC_VOLUME := "audio.music.volume"
const OPTION_EFFECTS := "audio.effects.enabled"
const OPTION_EFFECTS_VOLUME := "audio.effects.volume"
const SOUND_DIR := "res://assets/sound/"
const MUSIC_TRACK := "artificial_intelligence_v3.ogg"
## Sound names and their files.
const SOUNDS := {
	"click": "button_click.ogg",
	"rollover": "button_rollover.ogg",
	"turn": "turn_button_click.ogg",
	"new_turn": "newturn.ogg",
	"alert": "alert.ogg",
	"close": "window_close.ogg",
	"select": "item_select.ogg",
	"open": "sidepanel_open.ogg",
	"list_select": "list_select.ogg",
	"drop": "list_select.ogg",
	"pulldown": "list_pulldown.ogg",
	"fleet_click": "fleet_button_click.ogg",
	"fleet_rollover": "fleet_button_rollover.ogg",
	"system_rollover": "fleet_button_rollover.ogg",
}
## Panels and screens that sound as they open ("open") and close ("close").
const PANELS := [
	"SystemPanel",
	"PlanetPanel",
	"FleetPanel",
	"ShipPanel",
	"ProductionScreen",
	"ResearchScreen",
	"GovernmentScreen",
	"DesignerScreen",
	"ObjectsScreen",
	"CombatScreen",
	"EmpiresScreen",
	"PediaScreen",
	"ChatWindow",
]
## Hover ticks are quieter than clicks.
const ROLLOVER_DB := -9.0
const EFFECT_PLAYERS := 4

var music_enabled := true
var effects_enabled := true
## 0-255, as the options store them.
var music_volume := 127
var effects_volume := 255
## Sounds asked for so far, and the last one (also when nothing is heard).
var played_count := 0
var last_sound := ""
## Whether sounds are heard at all (see set_audible()).
var audible := false

var _music: AudioStreamPlayer
var _effects: Array[AudioStreamPlayer] = []
var _next_effect := 0
var _streams := {}


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	add_child(_music)
	for i in EFFECT_PLAYERS:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_effects.push_back(player)
	_read_options()
	get_tree().node_added.connect(_on_node_added)
	if is_instance_valid(get_node_or_null("/root/GlobalFreeOrionNode")):
		get_node("/root/GlobalFreeOrionNode").turn_update.connect(play.bind("new_turn"))
	_apply_music()


# Release the streams on the way out, or they outlive the audio server.
func _exit_tree() -> void:
	stop_all()


## Stop and drop every sound. The audio server frees playbacks on its next
## mix, so quit a few frames later (Shell.quit()) or they leak at exit.
func stop_all() -> void:
	for player: AudioStreamPlayer in [_music] + _effects:
		player.stop()
		player.stream = null
	_streams.clear()


## Play interface sound \a sound_name (a SOUNDS key), \a gain_db louder or
## quieter than the effects volume.
func play(sound_name: String, gain_db := 0.0) -> void:
	if not effects_enabled or effects_volume <= 0 or not SOUNDS.has(sound_name):
		return
	played_count += 1
	last_sound = sound_name
	if not audible:
		return
	var stream := _stream(SOUNDS[sound_name])
	if stream == null:
		return
	var player := _effects[_next_effect]
	_next_effect = (_next_effect + 1) % _effects.size()
	player.stream = stream
	player.volume_db = linear_to_db(effects_volume / 255.0) + gain_db
	player.play()


## Volume in dB for an option value 0-255.
static func volume_db(value: int) -> float:
	return linear_to_db(clampf(value / 255.0, 0.0001, 1.0))


func is_music_playing() -> bool:
	return _music.playing


## Let sounds be heard (the Shell does, unless headless). Streams still
## playing when a test run exits would be reported as leaked.
func set_audible(on: bool) -> void:
	audible = on
	_apply_music()


func _apply_music() -> void:
	if not music_enabled or not audible:
		_music.stop()
		return
	if _music.stream == null:
		var stream := _stream(MUSIC_TRACK)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		_music.stream = stream
	_music.volume_db = volume_db(music_volume)
	if _music.stream and not _music.playing:
		_music.play()


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		var path := SOUND_DIR + file
		_streams[file] = load(path) if ResourceLoader.exists(path) else null
	return _streams[file]


# A dragged item dropped somewhere that took it.
func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_DRAG_END
		and is_inside_tree()
		and get_viewport().gui_is_drag_successful()
	):
		play("drop")


# Buttons click when pressed and tick when hovered, unless they say otherwise;
# lists, panels and the map have their sounds (see the class description).
func _on_node_added(node: Node) -> void:
	if node is ItemList:
		node.item_selected.connect(func(_i): play("list_select"))
	elif node is Tree:
		node.item_selected.connect(play.bind("list_select"))
	var script: Script = node.get_script()
	var script_name := script.get_global_name() if script else &""
	if script_name in PANELS:
		node.visibility_changed.connect(_on_panel_visibility.bind(node))
	elif script_name == &"GalaxyMap":
		node.system_hovered.connect(_on_map_hover.bind("system_rollover"))
		node.fleet_hovered.connect(_on_map_hover.bind("fleet_rollover"))
		node.fleet_clicked.connect(func(_id): play("fleet_click"))
	if not node is BaseButton:
		return
	var button := node as BaseButton
	if (node is OptionButton or node is MenuButton) and not button.has_meta("sound"):
		button.set_meta("sound", "pulldown")
	button.pressed.connect(_on_button_pressed.bind(button))
	button.mouse_entered.connect(_on_button_hovered.bind(button))


func _on_map_hover(id: int, sound_name: String) -> void:
	if id >= 0:
		play(sound_name, ROLLOVER_DB)


func _on_panel_visibility(panel: CanvasItem) -> void:
	if panel.is_inside_tree():
		play("open" if panel.visible else "close")


func _on_button_pressed(button: BaseButton) -> void:
	var sound: String = button.get_meta("sound", "click")
	if not sound.is_empty():
		play(sound)


func _on_button_hovered(button: BaseButton) -> void:
	if not button.disabled and button.get_meta("sound", "click") != "":
		play("rollover", ROLLOVER_DB)


func _read_options() -> void:
	if not Engine.has_singleton("FOOptions") or Engine.is_editor_hint():
		return
	var options := Engine.get_singleton("FOOptions")
	options.add_option(OPTION_MUSIC, "OPTIONS_DB_MUSIC_ON", true)
	options.add_option(OPTION_MUSIC_VOLUME, "OPTIONS_DB_MUSIC_VOLUME", 127)
	options.add_option(OPTION_EFFECTS, "OPTIONS_DB_SOUND_ON", true)
	options.add_option(OPTION_EFFECTS_VOLUME, "OPTIONS_DB_UI_SOUND_VOLUME", 255)
	for option in [OPTION_MUSIC, OPTION_MUSIC_VOLUME, OPTION_EFFECTS, OPTION_EFFECTS_VOLUME]:
		_take(option, options.get_value(option))
		options.watch(option)
	options.option_changed.connect(_on_option_changed)


func _on_option_changed(option_name: String) -> void:
	if option_name.begins_with("audio."):
		_take(option_name, Engine.get_singleton("FOOptions").get_value(option_name))
		_apply_music()


func _take(option: String, value: Variant) -> void:
	match option:
		OPTION_MUSIC:
			music_enabled = bool(value)
		OPTION_MUSIC_VOLUME:
			music_volume = int(value)
		OPTION_EFFECTS:
			effects_enabled = bool(value)
		OPTION_EFFECTS_VOLUME:
			effects_volume = int(value)
