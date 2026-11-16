class_name GameMenu
extends Control
## In-game menu over a dimmed map (Esc or the top bar's Menu): resume, save,
## load, options, quit to the title, exit. Leaving asks for confirmation,
## since progress since the last save is lost. It only emits requests;
## GameShell opens the screens and Shell leaves the game.

signal resume_requested
## A full screen: "save", "load" or "options".
signal screen_requested(screen_name: String)
## Leave the game: "title" or "exit".
signal leave_requested(action: String)
## Give up the multiplayer game (confirmed).
signal concede_requested

## Screen entries: label key, screen.
const SCREEN_ENTRIES := [
	["GAME_MENU_SAVE", "save"],
	["GAME_MENU_LOAD", "load"],
	["OPTIONS_TITLE", "options"],
]

## The leave action awaiting confirmation, or "".
var pending_leave := ""
## Whether saving is possible now: () -> bool, asked again while the menu is
## open (the AI players may still be finishing their turn when it opens).
var save_check := Callable()
## The game's newest save, for the leave confirmation: () -> Dictionary
## ({turn, time, auto}, or {} when it was never saved). Unset: not shown.
var last_save := Callable()

var _subtitle: Label
var _entries: VBoxContainer
var _confirm: VBoxContainer
var _confirm_button: Button
var _resume: Button
var _save: Button
var _load: Button
var _concede: Button
var _warning: Label
var _saved_note: Label


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Modal: the dim layer takes clicks so the map below doesn't.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _gui_input(event: InputEvent) -> void:
	# A click on the dimmed map outside the card resumes.
	if event is InputEventMouseButton and event.pressed:
		resume_requested.emit()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if pending_leave.is_empty():
			resume_requested.emit()
		else:
			cancel_leave()
		get_viewport().set_input_as_handled()


## Show the menu; \a subtitle names the game (empire, turn). \a can_save is
## false while a turn is being processed. In a multiplayer game (\a is_multiplayer), Concede takes
## Load's place (disabled unless \a can_concede: the rules allow it).
func open(
	subtitle: String, can_save := true, is_multiplayer := false, can_concede := false
) -> void:
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	_set_can_save(can_save)
	_load.visible = not is_multiplayer
	_concede.visible = is_multiplayer
	_concede.disabled = not can_concede
	_concede.tooltip_text = "" if can_concede else tr("ERROR_CONCEDE_DISABLED")
	cancel_leave()
	visible = true
	FOUi.fade_in(self)
	_resume.call_deferred("grab_focus")


func _process(_delta: float) -> void:
	if visible and _save.disabled and save_check.is_valid():
		_set_can_save(save_check.call())


# Save enabled or not; when not, the tooltip says what it waits for.
func _set_can_save(can_save: bool) -> void:
	_save.disabled = not can_save
	_save.tooltip_text = "" if can_save else tr("GAME_MENU_SAVE_WAIT")


func close() -> void:
	visible = false
	pending_leave = ""


## Ask to confirm leaving with \a action ("title" or "exit"), or conceding
## ("concede").
func request_leave(action: String) -> void:
	pending_leave = action
	_entries.visible = false
	_confirm.visible = true
	_warning.text = tr("GAME_MENU_REALLY_CONCEDE" if action == "concede" else "MENU_CONFIRM_LEAVE")
	# What leaving would lose: since when the game was last saved.
	_saved_note.text = saved_note(last_save.call()) if last_save.is_valid() else ""
	_saved_note.visible = action != "concede" and not _saved_note.text.is_empty()
	match action:
		"title":
			_confirm_button.text = tr("MENU_QUIT_TO_TITLE")
		"concede":
			_confirm_button.text = tr("GAME_MENU_CONCEDE")
		_:
			_confirm_button.text = tr("TITLE_EXIT")
	_confirm_button.call_deferred("grab_focus")


## When \a save (SavesSource.newest_for()'s) was made: "Last saved on turn
## 40 (autosave), 2026-11-16 12:25", or that the game has no save yet.
static func saved_note(save: Dictionary) -> String:
	if save.is_empty():
		return TranslationServer.translate("GAME_MENU_NEVER_SAVED")
	var note := (
		TranslationServer
		. translate(
			"GAME_MENU_LAST_SAVED_AUTO" if save.get("auto", false) else "GAME_MENU_LAST_SAVED"
		)
		. replace("%1%", str(save.get("turn", 0)))
		. replace("%2%", SaveLoadScreen.format_time(str(save.get("time", ""))))
	)
	return note


func cancel_leave() -> void:
	pending_leave = ""
	_entries.visible = true
	_confirm.visible = false


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(FOUi.tokens.surface, 0.72)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = "OverlayPanel"
	card.custom_minimum_size.x = 320
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FOUi.tokens.space_2)
	card.add_child(box)
	var heading := ScreenKit.label(tr("GAME_MENU_WINDOW_TITLE"), "TitleLabel")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	_subtitle = ScreenKit.label("", "SecondaryLabel")
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_subtitle)

	_entries = VBoxContainer.new()
	_entries.add_theme_constant_override("separation", FOUi.tokens.space_2)
	box.add_child(_entries)
	_resume = _button(_entries, "MENU_RESUME", "PrimaryButton")
	_resume.pressed.connect(resume_requested.emit)
	for entry in SCREEN_ENTRIES:
		var button := _button(_entries, entry[0])
		button.pressed.connect(screen_requested.emit.bind(entry[1]))
		if entry[1] == "save":
			_save = button
		elif entry[1] == "load":
			_load = button
	_concede = _button(_entries, "GAME_MENU_CONCEDE")
	_concede.visible = false
	_concede.pressed.connect(request_leave.bind("concede"))
	_entries.move_child(_concede, _load.get_index() + 1)
	_entries.add_child(HSeparator.new())
	_button(_entries, "MENU_QUIT_TO_TITLE", "GhostButton").pressed.connect(
		request_leave.bind("title")
	)
	_button(_entries, "TITLE_EXIT", "GhostButton").pressed.connect(request_leave.bind("exit"))

	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", FOUi.tokens.space_3)
	_confirm.visible = false
	box.add_child(_confirm)
	_warning = ScreenKit.label(tr("MENU_CONFIRM_LEAVE"))
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning.custom_minimum_size.x = 280
	_confirm.add_child(_warning)
	_saved_note = ScreenKit.label("", "SecondaryLabel")
	_saved_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.add_child(_saved_note)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm.add_child(buttons)
	var cancel := Button.new()
	cancel.text = tr("CANCEL")
	cancel.pressed.connect(cancel_leave)
	buttons.add_child(cancel)
	_confirm_button = Button.new()
	_confirm_button.theme_type_variation = "DangerButton"
	_confirm_button.pressed.connect(_on_confirm_pressed)
	buttons.add_child(_confirm_button)


func _button(parent: Control, key: String, variation := "") -> Button:
	var button := Button.new()
	button.text = tr(key)
	button.theme_type_variation = variation
	parent.add_child(button)
	return button


func _on_confirm_pressed() -> void:
	var action := pending_leave
	if action.is_empty():
		return
	if action == "concede":
		cancel_leave()
		concede_requested.emit()
		return
	leave_requested.emit(action)
