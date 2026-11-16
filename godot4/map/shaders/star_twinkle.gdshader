shader_type canvas_item;
// The galaxy map's stars (GalaxyMap's multimesh of glow sprites): a hot
// white core and a slow twinkle, each star out of step with the others.

uniform float twinkle = 0.14;
uniform float speed = 1.1;
uniform float core = 0.55;

varying float phase;

void vertex() {
	phase = float(INSTANCE_ID) * 2.399;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = distance(UV, vec2(0.5));
	c.rgb = mix(c.rgb, vec3(1.0), smoothstep(0.16, 0.0, d) * core);
	float t = sin(TIME * speed + phase);
	COLOR = vec4(c.rgb * (1.0 + twinkle * t), c.a);
}
