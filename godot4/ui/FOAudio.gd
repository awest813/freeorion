extends Node
## Music and interface sounds (autoload "FOAudio"), from the audio.* options
## the GG client uses: music and effects on/off and volume (0-255). Every
## button clicks when pressed and ticks softly when hovered; a button can
## pick another sound with set_meta("sound", name) or none with "". The new
## turn has its own sound.

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
}
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
	# Headless runs (tests) have nothing to play to, and streams still
	# playing at exit would be reported as leaked.
	if _headless():
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


func _apply_music() -> void:
	if not music_enabled or _headless():
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


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _stream(file: String) -> AudioStream:
	if not _streams.has(file):
		var path := SOUND_DIR + file
		_streams[file] = load(path) if ResourceLoader.exists(path) else null
	return _streams[file]


# Buttons click when pressed and tick when hovered, unless they say otherwise.
func _on_node_added(node: Node) -> void:
	if not node is BaseButton:
		return
	var button := node as BaseButton
	button.pressed.connect(_on_button_pressed.bind(button))
	button.mouse_entered.connect(_on_button_hovered.bind(button))


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
