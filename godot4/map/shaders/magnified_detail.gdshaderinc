// Used by field.gdshader: grain that grows
// in as painted art is magnified, and a fade, so soft art stays textured
// when zoomed in (see field.gdshader).

// Screen pixels per texel at which the detail starts and is full.
uniform float detail_from = 1.2;
uniform float detail_full = 2.5;
// How far a field fades when it is magnified that much (0: not at all).
uniform float close_fade = 0.3;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	// Cells wrapped, so the hash keeps its precision far into the art.
	vec2 i = mod(floor(p), 4096.0);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(mod(i + vec2(1.0, 0.0), 4096.0)), u.x),
		mix(hash(mod(i + vec2(0.0, 1.0), 4096.0)), hash(mod(i + vec2(1.0, 1.0), 4096.0)), u.x),
		u.y
	);
}

// Four octaves at \a base cycles per texel.
float fbm(vec2 texels, float base) {
	float sum = 0.0;
	float amp = 0.5;
	vec2 p = texels * base;
	for (int i = 0; i < 4; i++) {
		sum += amp * noise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		amp *= 0.5;
	}
	return sum / 0.9375;
}

// Grain that stays fine on screen however far the art is magnified: the
// octaves step with the magnification (whole powers of two, so the pattern
// holds still while zooming) and blend across each step. The coarsest is
// 12 to 24 screen pixels across.
float detail(vec2 texels, float magnification) {
	float level = log2(max(magnification, 1.0));
	float step_down = floor(level);
	float blend = level - step_down;
	float fine = fbm(texels, exp2(step_down) / 12.0);
	float finer = fbm(texels, exp2(step_down + 1.0) / 12.0);
	return mix(fine, finer, blend);
}

// \a c (the art's colour) with detail for a pixel at \a uv of art whose texel
// is \a texel_size; untextured drawing (texel size 1) is left alone.
vec4 magnified_detail(vec4 c, vec2 uv, vec2 texel_size) {
	if (texel_size.x >= 0.02) {
		return c;
	}
	vec2 per_pixel = max(fwidth(uv), vec2(1e-7));
	float texels_per_pixel = max(per_pixel.x, per_pixel.y) / texel_size.x;
	float magnification = 1.0 / max(texels_per_pixel, 1e-4);
	float w = smoothstep(detail_from, detail_full, magnification);
	if (w > 0.0) {
		float n = detail(uv / texel_size, magnification);
		// Brighter wisps and darker gaps around the painted colour.
		c.rgb *= mix(1.0, 0.6 + 0.8 * n, w);
		c.a *= mix(1.0, 0.5 + 0.8 * n, w);
		c.a *= 1.0 - close_fade * w;
	}
	return c;
}
