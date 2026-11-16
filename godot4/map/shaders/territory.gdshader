shader_type canvas_item;
render_mode unshaded;
// Empire territories (GalaxyMap's supply group: a disk per supplied system in
// the empire's colour): an even fill where the disks overlap, and a crisp
// border where the territory ends or meets another empire's. The group's
// modulate alpha is the fill's; the border is `border_boost` times stronger.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float border_px = 1.5;
uniform float border_boost = 5.0;

vec4 at(vec2 uv) {
	vec4 c = textureLod(screen_texture, uv, 0.0);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	return c;
}

void fragment() {
	vec4 c = at(SCREEN_UV);
	if (c.a < 0.5) {
		COLOR = vec4(0.0);
	} else {
		vec2 o = SCREEN_PIXEL_SIZE * border_px;
		bool edge = false;
		for (int i = 0; i < 8; i++) {
			float a = float(i) * 0.785398;
			vec4 n = at(SCREEN_UV + vec2(cos(a), sin(a)) * o);
			edge = edge || n.a < 0.5 || distance(n.rgb, c.rgb) > 0.08;
		}
		float alpha = COLOR.a * (edge ? border_boost : 1.0);
		COLOR = vec4(c.rgb, clamp(alpha, 0.0, 0.85));
	}
}
