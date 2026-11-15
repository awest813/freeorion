class_name FORichText
extends RefCounted
## Converts FreeOrion text markup (stringtables, sitreps, Pedia) to Godot
## BBCode for RichTextLabel.
##
## - <i>, <u>, <b>, <s>             -> [i], [u], [b], [s]
## - <rgba r g b a>...</rgba>       -> [color=#rrggbbaa]...[/color]
## - <img src="icons/x.png">        -> inline image from the art directory
## - <url http://...>label</url>    -> [url=http://...]label[/url]
## - <encyclopedia KEY>, <planet 12>, <tech NAME>, ... (object links)
##                                   -> [url=fo://kind/arg]label[/url]
## - other tags are dropped, their text kept
## Square brackets in the text are escaped, so it can't inject BBCode.
## Handle clicks with parse_link(meta) in RichTextLabel.meta_clicked.

const LINK_SCHEME := "fo://"
const ART_DIR := "res://assets/art/"
const LINK_TAGS: Array[String] = [
	"encyclopedia",
	"planet",
	"system",
	"ship",
	"fleet",
	"building",
	"field",
	"combat",
	"empire",
	"shipdesign",
	"predefinedshipdesign",
	"tech",
	"policy",
	"buildingtype",
	"special",
	"shiphull",
	"shippart",
	"species",
	"fieldtype",
	"metertype",
	"browsepath",
	"graph",
]
const SIMPLE_TAGS := {"i": "i", "u": "u", "b": "b", "s": "s"}

static var _tag_regex: RegEx
static var _img_src_regex: RegEx


## Convert FreeOrion markup to BBCode. Inline images are \a image_height px high.
static func to_bbcode(text: String, image_height := 16) -> String:
	_compile()
	var out := ""
	var open_tags: Array[String] = []
	var pos := 0
	for match in _tag_regex.search_all(text):
		out += _escape(text.substr(pos, match.get_start() - pos))
		pos = match.get_end()
		var closing := match.get_string(1) == "/"
		var tag := match.get_string(2).to_lower()
		var param := match.get_string(3).strip_edges()
		if closing:
			out += _close(tag, open_tags)
		else:
			out += _open(tag, param, open_tags, image_height)
	out += _escape(text.substr(pos))
	# Close anything left open so the BBCode stays balanced.
	while not open_tags.is_empty():
		out += _closing_code(open_tags.pop_back())
	return out


## \a text with its FreeOrion markup tags removed (for the clipboard).
static func plain_text(text: String) -> String:
	_compile()
	return _tag_regex.sub(text, "", true)


## Split a link meta into {"kind": ..., "arg": ...}. Plain web links give
## kind "url" with the full address as arg.
static func parse_link(meta: String) -> Dictionary:
	if meta.begins_with(LINK_SCHEME):
		var rest := meta.substr(LINK_SCHEME.length())
		var slash := rest.find("/")
		if slash > 0:
			return {"kind": rest.substr(0, slash), "arg": rest.substr(slash + 1).uri_decode()}
	return {"kind": "url", "arg": meta}


static func _open(
	tag: String, param: String, open_tags: Array[String], image_height: int
) -> String:
	if SIMPLE_TAGS.has(tag):
		open_tags.push_back(tag)
		return "[%s]" % SIMPLE_TAGS[tag]
	if tag == "rgba":
		open_tags.push_back(tag)
		return "[color=%s]" % _rgba_to_html(param)
	if tag == "img":
		var src := _img_src_regex.search(param)
		if src == null:
			return ""
		return (
			"[img height=%d]%s%s[/img]" % [image_height, ART_DIR, src.get_string(1).strip_edges()]
		)
	if tag == "url" and not param.is_empty():
		open_tags.push_back(tag)
		return "[url=%s]" % param.replace("]", "%5D")
	if tag in LINK_TAGS and not param.is_empty():
		open_tags.push_back(tag)
		return "[url=%s%s/%s]" % [LINK_SCHEME, tag, param.uri_encode()]
	# Unknown or parameterless: keep the content, drop the tag.
	open_tags.push_back("")
	return ""


static func _close(tag: String, open_tags: Array[String]) -> String:
	# Close up to the matching open tag; ignore stray closing tags.
	var index := open_tags.rfind(tag)
	if index < 0:
		index = open_tags.rfind("")
		if index < 0:
			return ""
	var out := ""
	while open_tags.size() > index:
		out += _closing_code(open_tags.pop_back())
	return out


static func _closing_code(tag: String) -> String:
	if tag.is_empty():
		return ""
	if SIMPLE_TAGS.has(tag):
		return "[/%s]" % SIMPLE_TAGS[tag]
	if tag == "rgba":
		return "[/color]"
	return "[/url]"


static func _rgba_to_html(param: String) -> String:
	var parts := param.split(" ", false)
	var channels := PackedInt32Array([255, 255, 255, 255])
	for i in mini(parts.size(), 4):
		channels[i] = clampi(parts[i].to_int(), 0, 255)
	return "#%02x%02x%02x%02x" % [channels[0], channels[1], channels[2], channels[3]]


static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func _compile() -> void:
	if _tag_regex:
		return
	_tag_regex = RegEx.create_from_string("<(/?)([A-Za-z_]+)([^<>]*)>")
	_img_src_regex = RegEx.create_from_string('src\\s*=\\s*"([^"]*)"')
