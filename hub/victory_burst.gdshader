shader_type canvas_item;
render_mode unshaded;
// Локальный ореол: 20 лучей и тёплое свечение, без чтения экрана и размытия.
uniform vec4 accent : source_color = vec4(0.7, 0.4, 0.2, 1.0);
uniform vec4 gold : source_color = vec4(1.0, 0.67, 0.13, 1.0);
uniform float elapsed = 0.0;
uniform float reveal = 1.0;
uniform float warmth = 0.2;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float radius = length(p);
	float angle = atan(p.y, p.x) + elapsed * 6.2831853 / 50.0;
	float section = (angle / 6.2831853 + 1.0) * 20.0;
	float wedge = 1.0 - smoothstep(0.10, 0.39, abs(fract(section) - 0.5));
	float rays = wedge * smoothstep(0.4, 0.74, radius) * (1.0 - smoothstep(0.78, 1.0, radius));
	float glow = exp(-pow((radius - 0.68) / 0.22, 2.0)) * warmth;
	vec3 ray_color = mix(accent.rgb, gold.rgb, 0.22 + 0.42 * mod(floor(section), 2.0));
	vec3 color = mix(ray_color, gold.rgb, glow / max(0.001, glow + rays));
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float bounds_fade = smoothstep(0.0, 0.08, edge);
	COLOR = vec4(color, min(0.6, rays * 0.34 + glow) * reveal * bounds_fade);
}
