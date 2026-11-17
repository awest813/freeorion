class_name GalaxyPreview
extends Control
## Galaxy setup's preview of the galaxy shape: stars drawn where that shape
## puts them (spiral arms, an ellipse, a disc, a ring, clusters, ...), more
## of them for bigger galaxies, the same picture each time for a shape.

## Shape -> how its stars are placed.
const SHAPES := [
	"SPIRAL_2",
	"SPIRAL_3",
	"SPIRAL_4",
	"CLUSTER",
	"ELLIPTICAL",
	"DISC",
	"BOX",
	"IRREGULAR",
	"RING",
	"RANDOM",
]
## Stars drawn per system of the galaxy, within limits.
const STARS_PER_SYSTEM := 4
const STARS_MIN := 40
const STARS_MAX := 1100

static var _glow: Texture2D

var shape := "SPIRAL_2":
	set(value):
		shape = value
		_rebuild()
var systems := 150:
	set(value):
		systems = value
		_rebuild()

var _points := PackedVector2Array()
var _colors := PackedColorArray()
var _sizes := PackedFloat32Array()


func _init() -> void:
	clip_contents = true
	_rebuild()


## Star positions (unit square around the centre) for \a shape_name.
static func place(shape_name: String, count: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(shape_name)
	var points := PackedVector2Array()
	var clusters: Array[Vector2] = []
	for i in 6:
		clusters.push_back(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.2, 0.7))
	for i in count:
		var p := Vector2.ZERO
		match shape_name:
			"SPIRAL_2", "SPIRAL_3", "SPIRAL_4":
				var arms := int(shape_name.right(1))
				if rng.randf() < 0.18:
					p = Vector2(rng.randfn(0, 0.13), rng.randfn(0, 0.13))
				else:
					var t := pow(rng.randf(), 0.75)
					var angle := t * 3.4 + (i % arms) * TAU / arms + rng.randfn(0, 0.22)
					p = Vector2.from_angle(angle) * (0.08 + t * 0.86)
			"CLUSTER":
				var center: Vector2 = clusters[i % clusters.size()]
				p = center + Vector2(rng.randfn(0, 0.08), rng.randfn(0, 0.08))
			"ELLIPTICAL":
				p = Vector2(rng.randfn(0, 0.38), rng.randfn(0, 0.22)).rotated(0.4)
			"DISC":
				p = Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * 0.9
			"BOX":
				p = Vector2(rng.randf_range(-0.85, 0.85), rng.randf_range(-0.85, 0.85))
			"IRREGULAR":
				var blob: Vector2 = clusters[i % 3] * 0.8
				p = blob + Vector2(rng.randfn(0, 0.22), rng.randfn(0, 0.15)).rotated(i % 3)
			"RING":
				p = Vector2.from_angle(rng.randf() * TAU) * (0.68 + rng.randfn(0, 0.06))
			_:
				p = Vector2(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.9, 0.9))
		points.push_back(p.clamp(-Vector2.ONE, Vector2.ONE))
	return points


func _rebuild() -> void:
	var count := clampi(systems * STARS_PER_SYSTEM, STARS_MIN, STARS_MAX)
	_points = place(shape, count)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(shape) + 1
	_colors.resize(count)
	_sizes.resize(count)
	for i in count:
		var kind := rng.randi_range(0, MapStyle.STAR_COLORS.size() - 2)
		_colors[i] = MapStyle.star_color(kind)
		_sizes[i] = MapStyle.star_size(kind) * rng.randf_range(0.6, 1.2)
	queue_redraw()


func _draw() -> void:
	var tokens: FOTokens = FOUi.tokens
	draw_rect(Rect2(Vector2.ZERO, size), Color(tokens.glass_fill, 1.0))
	var side := minf(size.x, size.y) * 0.46
	var center := size / 2.0
	# A soft core where the shape has one.
	if shape.begins_with("SPIRAL") or shape in ["ELLIPTICAL", "DISC"]:
		var core := side * 0.55
		draw_texture_rect(
			_core_glow(), Rect2(center - Vector2.ONE * core, Vector2.ONE * core * 2.0), false
		)
	for i in _points.size():
		var at := center + _points[i] * side
		var radius := 1.4 * _sizes[i]
		draw_circle(at, radius * 2.6, Color(_colors[i], 0.12))
		draw_circle(at, radius, _colors[i])


# A radial glow, warm at the centre and fading out (made once: a gradient
# texture is filled in after it is made).
static func _core_glow() -> Texture2D:
	if _glow:
		return _glow
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.92, 0.78, 0.45))
	gradient.set_color(1, Color(1.0, 0.85, 0.7, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	_glow = texture
	return texture
