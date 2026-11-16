extends PanelContainer
## Every themed control in its states, on the current FOUi theme.
## Used as a design reference (run the scene) and by the screenshot tests.


func _ready() -> void:
	theme_type_variation = "BackgroundPanel"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", FOUi.tokens.space_8)
	margin.add_child(columns)
	columns.add_child(_type_and_buttons())
	columns.add_child(_inputs_and_panels())


func _type_and_buttons() -> Control:
	var box := _column()
	box.add_child(_label("Terran Imperium", "DisplayTitle"))
	box.add_child(_label("Galaxy overview", "HeadingLabel"))
	box.add_child(_label("Production queue", "TitleLabel"))
	box.add_child(_label("Body text: 12 systems explored, 3 colonised."))
	box.add_child(_label("Secondary text explains details.", "SecondaryLabel"))
	box.add_child(_label("Small caption, turn 42", "SmallLabel"))
	box.add_child(ScreenKit.section("Section caption"))
	box.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_child(_button("End turn", "PrimaryButton"))
	row.add_child(_button("Research"))
	row.add_child(_button("Cancel", "GhostButton"))
	row.add_child(_button("Leave game", "DangerButton"))
	box.add_child(row)

	var states := HBoxContainer.new()
	var disabled := _button("Disabled")
	disabled.disabled = true
	states.add_child(disabled)
	var toggled := _button("Toggled")
	toggled.toggle_mode = true
	toggled.button_pressed = true
	states.add_child(toggled)
	var focused := _button("Focused")
	states.add_child(focused)
	box.add_child(states)
	focused.grab_focus.call_deferred()

	var checks := HBoxContainer.new()
	var check := CheckBox.new()
	check.text = "Show supply"
	check.button_pressed = true
	checks.add_child(check)
	var toggle := CheckButton.new()
	toggle.text = "Auto-explore"
	checks.add_child(toggle)
	box.add_child(checks)
	return box


func _inputs_and_panels() -> Control:
	var box := _column()
	var name_edit := LineEdit.new()
	name_edit.text = "Fleet Alpha"
	box.add_child(name_edit)
	var search := LineEdit.new()
	search.placeholder_text = "Search the Pedia..."
	box.add_child(search)

	var progress := ProgressBar.new()
	progress.value = 62
	box.add_child(progress)
	var slider := HSlider.new()
	slider.value = 35
	box.add_child(slider)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 120)
	for tab_name in ["Planets", "Fleets", "Buildings"]:
		var page := VBoxContainer.new()
		page.name = tab_name
		page.add_child(_label("%s of the selected system" % tab_name))
		tabs.add_child(page)
	box.add_child(tabs)

	var overlay := PanelContainer.new()
	overlay.theme_type_variation = "OverlayPanel"
	overlay.add_child(_label("Overlay panel for tooltips and popups"))
	box.add_child(overlay)
	return box


func _column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return box


func _label(text: String, variation := "") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	return label


func _button(text: String, variation := "") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	return button
