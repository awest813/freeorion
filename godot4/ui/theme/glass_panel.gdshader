shader_type canvas_item;
// "Observatory glass" for panels (FOUi gives it to OverlayPanel, TopBarPanel
// and BackgroundPanel): where the panel's own fill is drawn (alpha at least
// `threshold`), what is behind it shows through, blurred, under the fill;
// with a faint grain so large areas aren't dead flat. Shadows and anti-aliased
// edges (lower alpha) draw as they are. Off (`enabled` false): unchanged.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform bool enabled = true;
// Distance between blur taps, in screen pixels (5x5 taps).
uniform float blur_px = 3.5;
uniform float threshold = 0.6;
uniform float grain = 0.018;

void fragment() {
	vec4 panel = COLOR;
	if (enabled && panel.a >= threshold) {
		vec2 tap = SCREEN_PIXEL_SIZE * blur_px;
		vec3 sum = vec3(0.0);
		float total = 0.0;
		for (int x = -2; x <= 2; x++) {
			for (int y = -2; y <= 2; y++) {
				float w = exp(-float(x * x + y * y) / 4.5);
				sum += texture(screen_texture, SCREEN_UV + vec2(float(x), float(y)) * tap).rgb * w;
				total += w;
			}
		}
		float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
		COLOR = vec4(mix(sum / total, panel.rgb, panel.a) + n * grain, 1.0);
	}
}
