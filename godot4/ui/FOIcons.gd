class_name FOIcons
extends RefCounted
## The interface's own icons (close, add, arrows, more, pause, locate, ...):
## one monochrome line set, drawn from SVG at the UI scale and tinted by the
## theme's icon colours. Game content (meters, techs, buildings) keeps its art.
##
## Buttons whose text is one of GLYPHS get the icon instead (FOUi.adopt()):
## the glyph stays in their "glyph" meta, for code and tests that look for it.

## Glyph used as a button text -> icon name.
const GLYPHS := {
	"✕": "close",
	"?": "info",
	"+": "add",
	"−": "remove",
	"▶": "play",
	"◀": "back",
	"⋯": "more",
	"▲": "up",
	"▼": "down",
	"Ⅱ": "pause",
	"☰": "menu",
	"⌖": "locate",
	"⌄": "dropdown",
	"⇥": "last",
}
## Icon name -> SVG body (24×24, white strokes; the theme tints it).
const SHAPES := {
	"close": '<path d="M6.5 6.5 17.5 17.5M17.5 6.5 6.5 17.5"/>',
	"info":
	(
		'<circle cx="12" cy="12" r="8.5"/><path d="M12 11v6"/>'
		+ '<circle cx="12" cy="7.6" r="0.6" fill="#fff"/>'
	),
	"add": '<path d="M12 5.5v13M5.5 12h13"/>',
	"remove": '<path d="M5.5 12h13"/>',
	"play": '<path d="M8.5 6.5 17 12l-8.5 5.5z" fill="#fff"/>',
	"back": '<path d="M15.5 6.5 7 12l8.5 5.5z" fill="#fff"/>',
	"more":
	(
		'<circle cx="6" cy="12" r="1.3" fill="#fff"/><circle cx="12" cy="12" r="1.3" fill="#fff"/>'
		+ '<circle cx="18" cy="12" r="1.3" fill="#fff"/>'
	),
	"up": '<path d="M6.5 14.5 12 9l5.5 5.5"/>',
	"down": '<path d="M6.5 9.5 12 15l5.5-5.5"/>',
	"pause": '<path d="M9 6.5v11M15 6.5v11"/>',
	"menu": '<path d="M5.5 7h13M5.5 12h13M5.5 17h13"/>',
	"locate": '<circle cx="12" cy="12" r="5.5"/><path d="M12 3.5v4M12 16.5v4M3.5 12h4M16.5 12h4"/>',
	"dropdown": '<path d="M7.5 10 12 14.5 16.5 10"/>',
	"last": '<path d="M5 12h10M11 7.5l4.5 4.5L11 16.5M19 6v12"/>',
}

static var _cache := {}


## Icon \a name at \a size pixels (scaled by the UI scale), or null.
static func icon(name: String, size: int) -> Texture2D:
	if not SHAPES.has(name):
		return null
	var px := maxi(8, roundi(size * (FOUi.scale if FOUi else 1.0)))
	var key := "%s@%d" % [name, px]
	if _cache.has(key):
		return _cache[key]
	var svg := (
		(
			'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"'
			+ ' fill="none" stroke="#fff" stroke-width="2.1" stroke-linecap="round"'
			+ ' stroke-linejoin="round">%s</svg>'
		)
		% SHAPES[name]
	)
	var image := Image.new()
	if image.load_svg_from_string(svg, px / 24.0) != OK:
		return null
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture


## The icon for \a glyph (a button text such as "✕"), or null.
static func for_glyph(glyph: String, size: int) -> Texture2D:
	return icon(GLYPHS.get(glyph, ""), size)
