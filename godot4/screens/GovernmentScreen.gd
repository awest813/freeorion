class_name GovernmentScreen
extends PanelContainer
## Government: policy slots by category on the left (adopted policies with
## revoke, empty slots; revert this turn's changes), policies on the right
## (GG's availability filters, category filter, search, adopt into the first
## free slot). Adopt is disabled, with the reason shown, when no slot is
## free, the policy is unaffordable or its prerequisites/exclusions block
## it. Policies drag onto slots and back off them; double-click adopts or
## revokes. Tooltips are GG's: cost, exclusions, prerequisites, turns
## adopted and the description.

signal close_requested
signal pedia_requested(kind: String, article_name: String)

## GG's availability filters: key, label key.
const AVAILABILITY := [
	["adopted", "POLICY_LIST_ADOPTED"],
	["adoptable", "POLICY_LIST_ADOPTABLE"],
	["unaffordable", "POLICY_LIST_UNAFFORDABLE"],
	["restricted", "POLICY_LIST_RESTRICTED"],
	["locked", "POLICY_LIST_LOCKED"],
]
const POLICY_DRAG := "fo_policy"
const SLOT_DRAG := "fo_policy_slot"

var source: Variant = GovernmentSource.new()
## Availabilities shown: key -> bool.
var shown := {
	"adopted": false, "adoptable": true, "unaffordable": true, "restricted": true, "locked": false
}

var _influence: Label
var _revert: Button
var _availability := {}
var _slots: VBoxContainer
var _filter: TabBar
var _search: LineEdit
var _catalog: VBoxContainer
var _categories: Array = []
var _policies: Array = []
var _slot_data: Array = []


func _init() -> void:
	# Texts are translated with tr() where needed; never auto-translate names.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	theme_type_variation = "BackgroundPanel"
	_build()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()


func refresh() -> void:
	_slot_data = source.get_slots()
	_policies = source.get_policies()
	var influence: Dictionary = source.get_influence()
	_influence.text = (
		tr("GOVERNMENT_INFLUENCE")
		. replace("%1%", "%.1f" % influence.get("stockpile", 0.0))
		. replace("%2%", "%.1f" % influence.get("adoption_cost", 0.0))
	)
	var categories: Array = _slot_data.map(func(s): return s["category"])
	if categories != _categories:
		_categories = categories
		var current := _filter.current_tab
		while _filter.tab_count > 0:
			_filter.remove_tab(0)
		_filter.add_tab(tr("PRODUCTION_FILTER_ALL"))
		for category in _categories:
			_filter.add_tab(tr(category))
		_filter.current_tab = clampi(current, 0, _filter.tab_count - 1)
	_revert.disabled = not source.is_modified()
	_revert.tooltip_text = tr(
		"GOVERNMENT_REVERT_NOTHING" if _revert.disabled else "GOVERNMENT_REVERT_TIP"
	)
	_refresh_slots()
	_refresh_catalog()


## Which of GG's availability filters \a policy falls under.
static func availability(policy: Dictionary) -> String:
	if policy.get("adopted", false):
		return "adopted"
	if not policy.get("available", true):
		return "locked"
	if not policy.get("prerequisites_ok", true):
		return "restricted"
	if not policy.get("affordable", true):
		return "unaffordable"
	return "adoptable"


## Show or hide policies of \a key's availability.
func set_shown(key: String, on: bool) -> void:
	shown[key] = on
	_availability[key].set_pressed_no_signal(on)
	_refresh_catalog()


## GG's policy tooltip: category and summary, cost and state, exclusions
## and prerequisites, turns adopted, description.
static func tooltip_for(policy: Dictionary) -> String:
	var t := TranslationServer.translate
	var lines := [
		(
			"%s - %s"
			% [t.call(policy.get("category", "")), t.call(policy.get("short_description", ""))]
		),
		""
	]
	var state := availability(policy)
	var cost_key: String = (
		{"adopted": "POLICY_ADOPTED", "locked": "POLICY_LOCKED", "restricted": "POLICY_RESTRICTED"}
		. get(state, "POLICY_ADOPTABLE_COST")
	)
	lines.push_back(t.call(cost_key).replace("%1%", "%.1f" % policy.get("cost", 0.0)))
	var conditions := []
	for excluder: String in policy.get("excluded_by", []):
		conditions.push_back(t.call("POLICY_EXCLUDED").replace("%1%", t.call(excluder)))
	for prereq: Dictionary in policy.get("prerequisites", []):
		var key := "POLICY_PREREQ_MET" if prereq.get("met", false) else "POLICY_PREREQ_MISSING"
		conditions.push_back(t.call(key).replace("%1%", t.call(prereq["name"])))
	if not conditions.is_empty():
		lines.push_back("")
		lines.append_array(conditions)
	if policy.has("total_turns"):
		var key := (
			"POLICY_ADOPTION_TIMES_CURRENT_AND_TOTAL"
			if state == "adopted"
			else "POLICY_ADOPTION_TIME_TOTAL"
		)
		lines.push_back("")
		lines.push_back(
			t.call(key).replace("%1%", str(policy.get("current_turns", 0))).replace(
				"%2%", str(policy["total_turns"])
			)
		)
	var description: String = policy.get("description", "")
	if not description.is_empty():
		lines.push_back("")
		lines.push_back(FORichText.plain_text(t.call(description)))
	return "\n".join(lines)


## First free slot index in \a category, or -1.
func free_slot(category: String) -> int:
	for slots: Dictionary in _slot_data:
		if slots["category"] == category:
			return slots["policies"].find("")
	return -1


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", FOUi.tokens.space_6)
	margin.add_child(columns)

	var slots_column := VBoxContainer.new()
	slots_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(slots_column)
	_influence = ScreenKit.header(slots_column, "MAP_BTN_GOVERNMENT", close_requested.emit)
	_revert = Button.new()
	_revert.text = tr("GOVERNMENT_WND_REVERT")
	_revert.theme_type_variation = "GhostButton"
	_revert.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_revert.pressed.connect(func(): _order(source.revert()))
	slots_column.add_child(_revert)
	_slots = ScreenKit.list()
	slots_column.add_child(ScreenKit.scrolling(_slots))

	var catalog_column := VBoxContainer.new()
	catalog_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(catalog_column)
	var availability_row := HFlowContainer.new()
	for entry in AVAILABILITY:
		var toggle := Button.new()
		toggle.text = tr(entry[1])
		toggle.toggle_mode = true
		toggle.button_pressed = shown[entry[0]]
		toggle.theme_type_variation = "SegmentButton"
		# (bind() would pass the key after the pressed state.)
		toggle.toggled.connect(func(on: bool): set_shown(entry[0], on))
		availability_row.add_child(toggle)
		_availability[entry[0]] = toggle
	catalog_column.add_child(availability_row)
	_filter = TabBar.new()
	_filter.tab_changed.connect(func(_t): _refresh_catalog())
	catalog_column.add_child(_filter)
	_search = LineEdit.new()
	_search.placeholder_text = tr("PRODUCTION_SEARCH")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_catalog())
	catalog_column.add_child(_search)
	_catalog = ScreenKit.list()
	var catalog_scroll := ScreenKit.scrolling(_catalog)
	# Adopted policies dragged back here are revoked.
	catalog_scroll.set_drag_forwarding(
		Callable(),
		func(_at, data): return data is Dictionary and data.get("type", "") == SLOT_DRAG,
		func(_at, data): _order(source.de_adopt(data["name"]))
	)
	catalog_column.add_child(catalog_scroll)


func _refresh_slots() -> void:
	ScreenKit.clear(_slots)
	for slots: Dictionary in _slot_data:
		_slots.add_child(ScreenKit.section(tr(slots["category"])))
		var policies: Array = slots["policies"]
		for i in policies.size():
			_slots.add_child(_slot_card(policies[i], slots["category"], i))
		# A category without slots yet says so rather than standing empty.
		if policies.is_empty():
			_slots.add_child(ScreenKit.label(tr("GOVERNMENT_NO_SLOTS"), "SecondaryLabel"))
	if _slot_data.is_empty():
		_slots.add_child(ScreenKit.label(tr("GOVERNMENT_NO_SLOTS"), "SecondaryLabel"))


func _slot_card(policy_name: String, category: String, slot: int) -> Control:
	var card := PanelContainer.new()
	card.set_meta("category", category)
	card.set_meta("policy", policy_name)
	card.add_theme_stylebox_override("panel", slot_style(category, policy_name.is_empty()))
	var row := HBoxContainer.new()
	card.add_child(row)
	# Policies of this category drop in; the adopted one drags out.
	card.set_drag_forwarding(
		func(_at):
			return {"type": SLOT_DRAG, "name": policy_name} if not policy_name.is_empty() else null,
		func(_at, data): return _can_drop_on_slot(data, category, policy_name),
		func(_at, data): drop_on_slot(data["name"], policy_name, slot)
	)
	if policy_name.is_empty():
		var empty := ScreenKit.label(tr("GOVERNMENT_EMPTY_SLOT"), "SecondaryLabel")
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.tooltip_text = tr("GOVERNMENT_EMPTY_SLOT_TIP")
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(empty)
		return card
	var policy := _policy(policy_name)
	card.tooltip_text = tooltip_for(policy)
	card.gui_input.connect(
		func(event: InputEvent):
			if event is InputEventMouseButton and event.double_click:
				_order(source.de_adopt(policy_name))
				card.accept_event()
	)
	row.add_child(ScreenKit.icon(policy.get("icon", ""), FOUi.tokens.icon_large))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	text.add_child(ScreenKit.label(tr(policy_name)))
	text.add_child(
		ScreenKit.label(
			tr("GOVERNMENT_UPKEEP").replace("%1%", "%.1f" % policy.get("cost", 0.0)), "SmallLabel"
		)
	)
	var info := ScreenKit.small_button("?", "PEDIA_OPEN")
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.pressed.connect(pedia_requested.emit.bind("policy", policy_name))
	row.add_child(info)
	var revoke := ScreenKit.small_button("✕", "GOVERNMENT_REVOKE")
	revoke.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	revoke.pressed.connect(func(): _order(source.de_adopt(policy_name)))
	row.add_child(revoke)
	return card


func _refresh_catalog() -> void:
	ScreenKit.clear(_catalog)
	var category: String = "" if _filter.current_tab <= 0 else _categories[_filter.current_tab - 1]
	var needle := _search.text.strip_edges().to_lower()
	var listed: Array = []
	for policy: Dictionary in _policies:
		if not shown.get(availability(policy), true):
			continue
		if not category.is_empty() and policy.get("category") != category:
			continue
		if not needle.is_empty() and not tr(policy["name"]).to_lower().contains(needle):
			continue
		listed.push_back(policy)
	# What can be adopted right now comes first; greyed rows (no free slot,
	# too dear, locked) follow, each group in name order.
	var now := {}
	for policy: Dictionary in listed:
		now[policy["name"]] = (
			availability(policy) == "adoptable" and free_slot(policy.get("category", "")) >= 0
		)
	listed.sort_custom(
		func(a, b):
			if now[a["name"]] != now[b["name"]]:
				return now[a["name"]]
			return tr(a["name"]).naturalnocasecmp_to(tr(b["name"])) < 0
	)
	for policy in listed:
		_catalog.add_child(_policy_row(policy))
	if listed.is_empty():
		_catalog.add_child(ScreenKit.label(tr("GOVERNMENT_NOTHING_MATCHES"), "SecondaryLabel"))


## The colour band of a policy card of \a category: economic, social and
## military each their own.
## The frame of a slot of \a category: tinted in the category's colour,
## faint and open while \a empty, with a band down the left once filled.
static func slot_style(category: String, empty: bool) -> StyleBoxFlat:
	var tokens: FOTokens = FOUi.tokens
	var band := category_band(category)
	var style := FOThemeBuilder.box(
		tokens,
		Color(band, 0.05) if empty else Color(tokens.surface_raised, 0.8),
		Color(band, 0.45 if empty else 0.3),
		tokens.space_3,
		tokens.space_3 if empty else tokens.space_2
	)
	if not empty:
		style.border_width_left = tokens.space_1
		style.border_color = band
		style.border_width_top = 0
		style.border_width_right = 0
		style.border_width_bottom = 0
	return FOThemeBuilder.cut(style, tokens, tokens.chamfer_small)


static func category_band(category: String) -> Color:
	var tokens: FOTokens = FOUi.tokens
	match category:
		"ECONOMIC_CATEGORY":
			return tokens.warning
		"SOCIAL_CATEGORY":
			return tokens.info
		"MILITARY_CATEGORY":
			return tokens.negative
	return tokens.text_secondary


func _policy_row(policy: Dictionary) -> Control:
	var policy_name: String = policy["name"]
	var row := HBoxContainer.new()
	row.tooltip_text = tooltip_for(policy)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var reason := _blocked_reason(policy)
	if not policy.get("adopted", false):
		row.set_drag_forwarding(
			func(_at):
				row.set_drag_preview(
					DesignerArt.drag_preview(
						FOArt.icon(policy.get("icon", "")), FOUi.tokens.icon_large
					)
				)
				return {"type": POLICY_DRAG, "name": policy_name},
			Callable(),
			Callable()
		)
	row.gui_input.connect(
		func(event: InputEvent):
			if not (event is InputEventMouseButton and event.double_click):
				return
			if policy.get("adopted", false):
				_order(source.de_adopt(policy_name))
			elif reason.is_empty():
				_order(source.adopt(policy_name, free_slot(policy.get("category", ""))))
			row.accept_event()
	)
	row.add_child(ScreenKit.icon(policy.get("icon", ""), FOUi.tokens.icon_large))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var title := ScreenKit.label(tr(policy_name))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var detail := (
		tr("GOVERNMENT_POLICY_DETAIL")
		. replace("%1%", "%.1f" % policy.get("cost", 0.0))
		. replace("%2%", tr(policy.get("category", "")))
	)
	if not reason.is_empty():
		detail += " · " + reason
	text.add_child(ScreenKit.label(detail, "SmallLabel"))
	var info := ScreenKit.small_button("?", "PEDIA_OPEN")
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.pressed.connect(pedia_requested.emit.bind("policy", policy_name))
	row.add_child(info)
	var adopt := Button.new()
	adopt.text = tr("GOVERNMENT_ADOPT")
	adopt.disabled = not reason.is_empty()
	adopt.visible = not policy.get("adopted", false)
	adopt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	adopt.pressed.connect(
		func(): _order(source.adopt(policy_name, free_slot(policy.get("category", ""))))
	)
	row.add_child(adopt)
	ScreenKit.card(row, category_band(policy.get("category", "")))
	return row


## Adopt \a policy_name into \a slot, replacing \a current there.
func drop_on_slot(policy_name: String, current: String, slot: int) -> void:
	if not current.is_empty():
		source.de_adopt(current)
	# Shown afresh even when the adoption fails: the revoke went through.
	source.adopt(policy_name, slot)
	refresh.call_deferred()


# Whether \a data is a policy of \a category that can go into a slot
# holding \a current.
# A policy dragged: the slots it can go into are outlined, the others fade
# (as the designer lights the slots a part fits).
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		highlight_slots_for(get_viewport().gui_get_drag_data())
	elif what == NOTIFICATION_DRAG_END:
		highlight_slots_for(null)


## Mark the slots \a data (a dragged policy, or null for none) can go into.
func highlight_slots_for(data: Variant) -> void:
	var dragging: bool = data is Dictionary and data.get("type", "") == POLICY_DRAG
	var t: FOTokens = FOUi.tokens
	for card: Node in _slots.get_children():
		if not card.has_meta("category"):
			continue
		var fits := (
			dragging and _can_drop_on_slot(data, card.get_meta("category"), card.get_meta("policy"))
		)
		card.modulate.a = 0.4 if dragging and not fits else 1.0
		if fits:
			var style := FOThemeBuilder.box(t, t.surface_raised, t.accent, t.space_3, t.space_2)
			style.set_border_width_all(t.focus_width)
			card.add_theme_stylebox_override("panel", style)
		else:
			card.remove_theme_stylebox_override("panel")


func _can_drop_on_slot(data: Variant, category: String, current: String) -> bool:
	if not (data is Dictionary and data.get("type", "") == POLICY_DRAG):
		return false
	var policy := _policy(data["name"])
	return (
		policy.get("category", "") == category
		and data["name"] != current
		and policy.get("available", true)
		and policy.get("prerequisites_ok", true)
		and policy.get("affordable", true)
	)


# Why a policy can't be adopted now, or "" if it can.
func _blocked_reason(policy: Dictionary) -> String:
	if policy.get("adopted", false):
		return ""
	if not policy.get("available", true):
		return tr("POLICY_LIST_LOCKED")
	if free_slot(policy.get("category", "")) < 0:
		return tr("GOVERNMENT_NO_FREE_SLOT")
	if not policy.get("prerequisites_ok", true):
		return tr("GOVERNMENT_BLOCKED")
	if not policy.get("affordable", true):
		return tr("GOVERNMENT_UNAFFORDABLE")
	return ""


func _policy(policy_name: String) -> Dictionary:
	for policy: Dictionary in _policies:
		if policy["name"] == policy_name:
			return policy
	return {}


func _order(ok: bool) -> void:
	if ok:
		refresh.call_deferred()
