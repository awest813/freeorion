class_name FODialog
extends Control
## Modal message over a dimmed screen: a title, a message and buttons. Each
## button closes the dialog, then runs its action; Esc presses the last
## button (the cancel or "keep going" choice). Use FODialog.open_on().

## Buttons: [label, theme variation, action Callable (may be empty)].
var buttons: Array = []

var _title: Label
var _message: Label
var _row: HBoxContainer


func _init() -> void:
	# Texts are translated by the caller; never auto-translate them.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


## Show a dialog over \a parent (added as its last child, so on top).
static func open_on(parent: Node, title: String, message: String, choices: Array) -> FODialog:
	var dialog := FODialog.new()
	dialog.set_content(title, message, choices)
	parent.add_child(dialog)
	FOUi.fade_in(dialog)
	var audio := dialog.get_node_or_null("/root/FOAudio")
	if audio:
		audio.play("alert")
	return dialog


func set_content(title: String, message: String, choices: Array) -> void:
	_title.text = title
	_message.text = message
	buttons = choices
	ScreenKit.clear(_row)
	for choice in choices:
		var button := Button.new()
		button.text = choice[0]
		button.theme_type_variation = choice[1]
		button.pressed.connect(choose.bind(_row.get_child_count()))
		_row.add_child(button)
	if _row.get_child_count() > 0:
		# Enter does the first choice, unless it destroys something: then
		# the focus starts on the way out (the last choice), as Esc does.
		var first: String = choices[0][1]
		var start := _row.get_child_count() - 1 if first == "DangerButton" else 0
		_row.get_child(start).call_deferred("grab_focus")


## Put \a control between the message and the buttons (a list, a check box).
func add_content(control: Control) -> void:
	_row.get_parent().add_child(control)
	_row.get_parent().move_child(control, _row.get_index())


## Close the dialog and run the action of button \a index.
func choose(index: int) -> void:
	var action: Callable = buttons[index][2] if buttons[index].size() > 2 else Callable()
	queue_free()
	visible = false
	if action.is_valid():
		action.call()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not buttons.is_empty():
		choose(buttons.size() - 1)
		get_viewport().set_input_as_handled()


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
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FOUi.tokens.space_3)
	card.add_child(box)
	_title = ScreenKit.label("", "TitleLabel")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_message = ScreenKit.label("")
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size.x = 360
	box.add_child(_message)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_row)
