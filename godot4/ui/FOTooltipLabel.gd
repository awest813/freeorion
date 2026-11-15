class_name FOTooltipLabel
extends Label
## A label whose tooltip is built when it opens, by \a tooltip_builder (a
## Callable returning a Control), so costly content (meter breakdowns) is
## only fetched when someone hovers. tooltip_text must not be empty for
## Godot to show a tooltip; it is also the fallback text.

var tooltip_builder: Callable


func _make_custom_tooltip(for_text: String) -> Object:
	if not tooltip_builder.is_valid():
		return null
	var content: Control = tooltip_builder.call()
	if content == null:
		return ScreenKit.label(for_text)
	return content
