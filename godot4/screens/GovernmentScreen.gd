class_name GovernmentScreen
extends PanelContainer
## Government: policy slots by category on the left (adopted policies with
## revoke, empty slots), available policies on the right (category filter,
## search, adopt into the first free slot). Adopt is disabled, with the
## reason shown, when no slot is free, the policy is unaffordable or its
## prerequisites/exclusions block it.

signal close_requested
signal pedia_requested(kind: String, article_name: String)

var source: Variant = GovernmentSource.new()

var _influence: Label
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
	_refresh_slots()
	_refresh_catalog()


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
	_slots = ScreenKit.list()
	slots_column.add_child(ScreenKit.scrolling(_slots))

	var catalog_column := VBoxContainer.new()
	catalog_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(catalog_column)
	_filter = TabBar.new()
	_filter.tab_changed.connect(func(_t): _refresh_catalog())
	catalog_column.add_child(_filter)
	_search = LineEdit.new()
	_search.placeholder_text = tr("PRODUCTION_SEARCH")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_catalog())
	catalog_column.add_child(_search)
	_catalog = ScreenKit.list()
	catalog_column.add_child(ScreenKit.scrolling(_catalog))


func _refresh_slots() -> void:
	ScreenKit.clear(_slots)
	for slots: Dictionary in _slot_data:
		_slots.add_child(ScreenKit.label(tr(slots["category"]), "TitleLabel"))
		for policy_name: String in slots["policies"]:
			_slots.add_child(_slot_card(policy_name))
	if _slot_data.is_empty():
		_slots.add_child(ScreenKit.label(tr("GOVERNMENT_NO_SLOTS"), "SecondaryLabel"))


func _slot_card(policy_name: String) -> Control:
	var card := PanelContainer.new()
	var row := HBoxContainer.new()
	card.add_child(row)
	if policy_name.is_empty():
		var empty := ScreenKit.label(tr("GOVERNMENT_EMPTY_SLOT"), "SecondaryLabel")
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(empty)
		return card
	var policy := _policy(policy_name)
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
	var shown: Array = []
	for policy: Dictionary in _policies:
		if policy.get("adopted", false):
			continue
		if not category.is_empty() and policy.get("category") != category:
			continue
		if not needle.is_empty() and not tr(policy["name"]).to_lower().contains(needle):
			continue
		shown.push_back(policy)
	shown.sort_custom(func(a, b): return tr(a["name"]).naturalnocasecmp_to(tr(b["name"])) < 0)
	for policy in shown:
		_catalog.add_child(_policy_row(policy))
	if shown.is_empty():
		_catalog.add_child(ScreenKit.label(tr("GOVERNMENT_NOTHING_MATCHES"), "SecondaryLabel"))


func _policy_row(policy: Dictionary) -> Control:
	var policy_name: String = policy["name"]
	var row := HBoxContainer.new()
	row.tooltip_text = tr(policy.get("short_description", ""))
	row.add_child(ScreenKit.icon(policy.get("icon", ""), FOUi.tokens.icon_large))
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	row.add_child(text)
	var title := ScreenKit.label(tr(policy_name))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var reason := _blocked_reason(policy)
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
	adopt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	adopt.pressed.connect(
		func(): _order(source.adopt(policy_name, free_slot(policy.get("category", ""))))
	)
	row.add_child(adopt)
	return row


# Why a policy can't be adopted now, or "" if it can.
func _blocked_reason(policy: Dictionary) -> String:
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
