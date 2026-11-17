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
## Everything's volume (the Master bus), 0-255.
const OPTION_MASTER_VOLUME := "audio.master.volume"
## Seconds the music takes to come in or go.
const MUSIC_FADE_SECONDS := 1.5
const SOUND_DIR := "res://assets/sound/"
const MUSIC_TRACK := "artificial_intelligence_v3.ogg"
## Sound names and their files.
const SOUNDS := {
	"click": "button_click.ogg",
	"rollover": "button_rollover.ogg",
	"turn": "turn_button_click.ogg",
	"new_turn": "newturn.ogg",
	"alert": "alert.ogg",
	"combat": "combat/explosion-med1.ogg",
	"close": "window_close.ogg",
	"select": "item_select.ogg",
	"open": "sidepanel_open.ogg",
	"list_select": "list_select.ogg",
	"drop": "list_select.ogg",
	"pulldown": "list_pulldown.ogg",
	"fleet_click": "fleet_button_click.ogg",
	"fleet_rollover": "fleet_button_rollover.ogg",
	"system_rollover": "fleet_button_rollover.ogg",
	# A planet's new focus (sounds the game ships for them, GG left unused).
	"focus_industry": "industry_select.ogg",
	"focus_research": "research_select.ogg",
	"focus_growth": "farm_select.ogg",
	"focus_stockpile": "mining_select.ogg",
	"focus": "balanced_select.ogg",
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
## The music's bus, and its low-pass cutoff in peace and when fighting.
const MUSIC_BUS := "Music"
const CALM_HZ := 3200.0
const TENSE_HZ := 20000.0
const TENSION_SECONDS := 4.0

var music_enabled := true
var effects_enabled := true
## 0-255, as the options store them.
var music_volume := 127
var effects_volume := 255
var master_volume := 255
## Sounds asked for so far, and the last one (also when nothing is heard).
var played_count := 0
var last_sound := ""
## Whether sounds are heard at all (see set_audible()).
var audible := false

var _music: AudioStreamPlayer
var _music_fade: Tween
var _lowpass: AudioEffectLowPassFilter
var _effects: Array[AudioStreamPlayer] = []
var _next_effect := 0
var _streams := {}


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.bus = _music_bus()
	add_child(_music)
	for i in EFFECT_PLAYERS:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_effects.push_back(player)
	_read_options()
	get_tree().node_added.connect(_on_node_added)
	if is_instance_valid(get_node_or_null("/root/GlobalFreeOrionNode")):
		get_node("/root/GlobalFreeOrionNode").turn_update.connect(play.bind("new_turn"))
		get_node("/root/GlobalFreeOrionNode").combat_logs_updated.connect(_on_combats)
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
	AudioServer.set_bus_volume_db(0, volume_db(master_volume))
	if _music_fade:
		_music_fade.kill()
	if not music_enabled or not audible:
		# Fades out, rather than cutting off.
		if _music.playing and audible:
			_music_fade = create_tween()
			_music_fade.tween_property(_music, "volume_db", -60.0, MUSIC_FADE_SECONDS)
			_music_fade.tween_callback(_music.stop)
		else:
			_music.stop()
		return
	if _music.stream == null:
		var stream := _stream(MUSIC_TRACK)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		_music.stream = stream
	if _music.stream and not _music.playing:
		# Comes in from silence.
		_music.volume_db = -60.0
		_music.play()
	_music_fade = create_tween()
	_music_fade.tween_property(_music, "volume_db", volume_db(music_volume), MUSIC_FADE_SECONDS)


## Let the music open up (\a tense: the empire fought in the last turn) or
## settle back, muffled, in peace; over a few seconds.
func set_tension(tense: bool) -> void:
	if _lowpass == null:
		return
	var target := TENSE_HZ if tense else CALM_HZ
	if is_equal_approx(_lowpass.cutoff_hz, target):
		return
	create_tween().tween_property(_lowpass, "cutoff_hz", target, TENSION_SECONDS)


func is_tense() -> bool:
	return _lowpass != null and _lowpass.cutoff_hz > (CALM_HZ + TENSE_HZ) / 2.0


# A bus of its own for the music, behind a low-pass filter that follows the
# tension (set_tension()).
func _music_bus() -> String:
	var index := AudioServer.get_bus_index(MUSIC_BUS)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, MUSIC_BUS)
		AudioServer.set_bus_send(index, "Master")
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = CALM_HZ
		AudioServer.add_bus_effect(index, _lowpass)
	else:
		_lowpass = AudioServer.get_bus_effect(index, 0) as AudioEffectLowPassFilter
	return MUSIC_BUS


# Combat reports arrived: tense when one of them is from the last turn.
func _on_combats() -> void:
	var turn: int = get_node("/root/GlobalFreeOrionNode").get_current_turn()
	set_tension(FOCombat.list_combats().any(func(c): return c.get("turn", 0) >= turn - 1))


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		var path := SOUND_DIR + file
		_streams[file] = load(path) if ResourceLoader.exists(path) else null
	return _streams[file]


# A dragged item dropped somewhere that took it. The music pauses while
# the window is in the background, and goes on from there (as GG's).
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			set_window_focused(false)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			set_window_focused(true)
		NOTIFICATION_DRAG_END:
			if is_inside_tree() and get_viewport().gui_is_drag_successful():
				play("drop")


## Pause the music while the window isn't \a focused; resume it after.
func set_window_focused(focused: bool) -> void:
	if _music:
		_music.stream_paused = not focused


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
	if node.has_signal("focus_requested"):
		node.focus_requested.connect(func(_planet_id: int, focus: String): play(focus_sound(focus)))
	if not node is BaseButton:
		return
	var button := node as BaseButton
	if (node is OptionButton or node is MenuButton) and not button.has_meta("sound"):
		button.set_meta("sound", "pulldown")
	button.pressed.connect(_on_button_pressed.bind(button))
	button.mouse_entered.connect(_on_button_hovered.bind(button))


## The sound of a planet taking \a focus ("FOCUS_INDUSTRY"): its own where
## the game has one, else a general one.
static func focus_sound(focus: String) -> String:
	var own := "focus_" + focus.trim_prefix("FOCUS_").to_lower()
	return own if SOUNDS.has(own) else "focus"


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
	options.add_option(OPTION_MASTER_VOLUME, "OPTIONS_DB_MASTER_VOLUME", 255)
	for option in [OPTION_MUSIC, OPTION_MUSIC_VOLUME, OPTION_EFFECTS, OPTION_EFFECTS_VOLUME]:
		_take(option, options.get_value(option))
		options.watch(option)
	_take(OPTION_MASTER_VOLUME, options.get_value(OPTION_MASTER_VOLUME))
	options.watch(OPTION_MASTER_VOLUME)
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
		OPTION_MASTER_VOLUME:
			master_volume = int(value)
