shader_type canvas_item;
// A planet on a quad: the equirectangular `surface` wrapped onto a sphere
// (radius `radius` of the half-size), turning at `spin` (radians a second),
// lit from `light_dir` in `light_color` with a soft terminator, an
// atmosphere rim and a faint halo in `atmosphere`.

uniform sampler2D surface : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 atmosphere : source_color = vec4(0.45, 0.7, 1.0, 0.8);
uniform vec4 light_color : source_color = vec4(1.0, 0.97, 0.9, 1.0);
uniform vec3 light_dir = vec3(-0.75, -0.35, 0.55);
uniform float radius = 0.86;
uniform float spin = 0.08;
uniform float phase = 0.0;
uniform float ambient = 0.07;



void fragment() {
	vec2 p = (UV * 2.0 - 1.0) / radius;
	float r2 = dot(p, p);
	vec3 l = normalize(light_dir);
	if (r2 > 1.0) {
		// Halo just outside the limb, brighter on the lit side.
		float d = sqrt(r2) - 1.0;
		float lit = clamp(dot(normalize(vec3(p, 0.0)), l) * 0.5 + 0.6, 0.0, 1.0);
		float halo = exp(-d * 18.0) * atmosphere.a * 0.55 * lit;
		COLOR = vec4(atmosphere.rgb, halo);
	} else {
		vec3 n = vec3(p.x, -p.y, sqrt(1.0 - r2));
		float lon = atan(n.x, n.z) + phase + TIME * spin;
		float lat = asin(clamp(n.y, -1.0, 1.0));
		vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
		vec3 albedo = texture(surface, uv).rgb;
		vec3 ln = vec3(l.x, -l.y, l.z);
		float diffuse = smoothstep(-0.12, 0.6, dot(n, normalize(ln)));
		vec3 color = albedo * (ambient + diffuse * light_color.rgb);
		// Atmosphere: thicker towards the limb, lit with the day side.
		float rim = pow(1.0 - n.z, 2.5);
		color += atmosphere.rgb * rim * atmosphere.a * (0.25 + 0.75 * diffuse);
		// Anti-aliased limb.
		float edge = smoothstep(1.0, 1.0 - 0.04 / radius, sqrt(r2));
		COLOR = vec4(color, edge);
	}
}
