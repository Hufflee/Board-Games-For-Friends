shader_type spatial;
// Экран ЭЛТ-телевизора: выпуклое стекло, строки развёртки, мерцание, виньетка и блик.
render_mode unshaded, cull_back;

uniform vec4 base_color : source_color = vec4(0.04, 0.55, 0.75, 1.0);
uniform vec4 glow_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
uniform float bulge = 0.012;
uniform float brightness = 1.4;

void vertex() {
	vec2 c = UV * 2.0 - 1.0;
	VERTEX.z += bulge * (1.0 - c.x * c.x) * (1.0 - c.y * c.y);
}

void fragment() {
	vec2 uv = UV;
	vec2 c = uv * 2.0 - 1.0;
	float vign = smoothstep(1.35, 0.45, length(c * vec2(0.95, 1.05)));
	float scan = 0.82 + 0.18 * sin(uv.y * 520.0);
	float roll = 0.94 + 0.06 * sin(uv.y * 8.0 - TIME * 3.0);
	float flicker = 0.97 + 0.03 * sin(TIME * 37.0);
	vec3 col = mix(base_color.rgb, glow_color.rgb, smoothstep(0.9, 0.0, length(c)) * 0.45);
	col *= scan * roll * flicker * vign * brightness;
	// блик на стекле
	float spec = smoothstep(0.35, 0.0, length(c - vec2(-0.45, 0.5)) ) * 0.35;
	col += vec3(spec);
	ALBEDO = col;
}
