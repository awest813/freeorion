class_name MeterGrid
extends GridContainer
## Meter rows of a planet or ship: icon, name, value this turn with next
## turn's change, and the target or maximum it moves to. Hovering a name
## lists the effects behind the value, as the GG meter tooltips do.
## Meters that are zero throughout (an empty planet's industry) are left out.

## Meter icons (icons/meter/*.png) where the file isn't the meter's name.
const METER_ICONS := {
	"METER_REBEL_TROOPS": "rebels",
	"METER_POPULATION": "pop",
	"METER_HAPPINESS": "happiness",
	"METER_CONSTRUCTION": "construction",
}
## Changes smaller than this show as steady.
const STEADY := 0.05

## The planet or ship the meters belong to.
var object_id := -1
## Returns get_meter_accounting() for (object_id, meter); tests replace it.
var accounting_provider := func(id: int, meter: String) -> Dictionary:
	return FOUniverse.get_meter_accounting(id, meter)


func _init() -> void:
	columns = 4
	add_theme_constant_override("h_separation", FOUi.tokens.space_2)
	add_theme_constant_override("v_separation", 0)


## Show \a meters: {meter, now, next, target (if any), accounting_meter},
## as FOUniverse.get_planet_detail() and get_ship_detail() give them.
func fill(meters: Array) -> void:
	ScreenKit.clear(self)
	for meter: Dictionary in meters:
		var now: float = meter.get("now", 0.0)
		var next: float = meter.get("next", 0.0)
		var target: float = meter.get("target", next)
		if absf(now) < STEADY and absf(next) < STEADY and absf(target) < STEADY:
			continue
		var key: String = meter.get("meter", "")
		var icon_name: String = METER_ICONS.get(key, key.trim_prefix("METER_").to_lower())
		add_child(ScreenKit.icon("icons/meter/%s.png" % icon_name, FOUi.tokens.icon_small))
		# Hovering the name explains the value, effect by effect.
		var label := FOTooltipLabel.new()
		label.text = tr(key)
		label.tooltip_text = tr(key)
		label.theme_type_variation = "SmallLabel"
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_builder = accounting_tooltip.bind(meter.get("accounting_meter", key))
		add_child(label)
		var tip := (
			tr("PLANET_PANEL_METER_TIP")
			. replace("%1%", tr(key))
			. replace("%2%", "%.1f" % now)
			. replace("%3%", "%.1f" % next)
			. replace("%4%", "%.1f" % target)
		)
		var value := ScreenKit.label("%.1f" % now)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.tooltip_text = tip
		var change := change_text(now, next)
		if not change.is_empty():
			value.text += " " + change
			value.add_theme_color_override(
				"font_color", FOUi.tokens.positive if next > now else FOUi.tokens.negative
			)
		add_child(value)
		var goal := ScreenKit.label("", "SmallLabel")
		if meter.has("target"):
			goal.text = "/ %.1f" % target
			goal.tooltip_text = tr("PLANET_PANEL_TARGET")
		add_child(goal)


## Text for a meter's change: "+0.4", "−1.0", or "" when steady.
static func change_text(now: float, next: float) -> String:
	var change := next - now
	if absf(change) < STEADY:
		return ""
	return ("+%.1f" if change > 0.0 else "−%.1f") % absf(change)


## Tooltip content for \a meter: its total, then each effect with its
## change; null (plain tooltip) when no breakdown is known.
func accounting_tooltip(meter: String) -> Control:
	var accounting: Dictionary = accounting_provider.call(object_id, meter)
	var lines: Array = accounting.get("lines", [])
	if lines.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(
		ScreenKit.label(
			tr("TT_BREAKDOWN_SUMMARY").replace("%1%", tr(meter)).replace(
				"%2%", "%.2f" % accounting.get("total", 0.0)
			),
			"TitleLabel"
		)
	)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", FOUi.tokens.space_4)
	box.add_child(grid)
	for line: Dictionary in lines:
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.autowrap_mode = TextServer.AUTOWRAP_OFF
		text.custom_minimum_size.x = 280
		text.text = FORichText.to_bbcode(line.get("label", ""))
		grid.add_child(text)
		var change: float = line.get("change", 0.0)
		var value := ScreenKit.label("%+.2f" % change)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_color_override(
			"font_color", FOUi.tokens.positive if change >= 0.0 else FOUi.tokens.negative
		)
		grid.add_child(value)
	return box
