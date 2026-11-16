class_name AlertCards
extends VBoxContainer
## The turn's important events as cards under the top bar: battles the
## empire was in, ground battles, own ships destroyed, planets depopulated
## or captured. Each card has the event's icon and text (its links work)
## and a close button; at most a few at once, and they fade away by
## themselves after a while so they never stay in the way.

signal link_activated(kind: String, arg: String)

## Sitrep labels worth a card.
const LABELS := [
	"SITREP_COMBAT_SYSTEM_LABEL",
	"SITREP_COMBAT_SYSTEM_ENEMY_LABEL",
	"SITREP_GROUND_BATTLE_LABEL",
	"SITREP_GROUND_BATTLE_ENEMY_LABEL",
	"SITREP_OWN_SHIP_DESTROYED_AT_SYSTEM_LABEL",
	"SITREP_PLANET_DEPOPULATED_LABEL",
	"SITREP_PLANET_CAPTURED_LABEL",
]
const MAX_CARDS := 3
## Seconds a card stays before it fades.
const STAY := 10.0
const WIDTH := 440


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", FOUi.tokens.space_2)
	custom_minimum_size.x = WIDTH


## The cards for this turn's \\a sitreps (get_sitreps()): the old ones go.
func show_turn(sitreps: Array) -> void:
	ScreenKit.clear(self)
	var shown := 0
	for sitrep: Dictionary in important(sitreps):
		if shown >= MAX_CARDS:
			break
		add_child(_card(sitrep))
		shown += 1


## The sitreps of \\a sitreps worth a card, in order.
static func important(sitreps: Array) -> Array:
	return sitreps.filter(func(s): return LABELS.has(s.get("label", "")))


func _card(sitrep: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "OverlayPanel"
	var row := HBoxContainer.new()
	card.add_child(row)
	row.add_child(ScreenKit.icon(sitrep.get("icon", ""), FOUi.tokens.icon))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = FORichText.to_bbcode(sitrep.get("text", ""), FOUi.tokens.icon_small)
	text.meta_clicked.connect(
		func(meta: Variant):
			var link := FORichText.parse_link(str(meta))
			link_activated.emit(link["kind"], link["arg"])
	)
	row.add_child(text)
	var close := ScreenKit.small_button("✕", "PANEL_CLOSE")
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(card.queue_free)
	row.add_child(close)
	if not FOUi.reduce_motion:
		FOUi.fade_in(card)
	var tween := card.create_tween()
	tween.tween_interval(STAY)
	tween.tween_property(card, "modulate:a", 0.0, FOUi.tokens.motion * 3.0)
	tween.tween_callback(card.queue_free)
	return card
