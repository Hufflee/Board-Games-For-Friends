shader_type canvas_item;
uniform vec4 paper : source_color;
uniform vec4 ink : source_color;
uniform vec2 surface_size = vec2(1280.0, 720.0);
uniform vec2 ring_center = vec2(640.0, 360.0);
uniform vec2 motion = vec2(0.0);
void fragment() {
	vec2 p = UV * surface_size / surface_size.y;
	float rings = abs(sin(length(p - ring_center / surface_size.y) * 52.0));
	float line = 1.0 - smoothstep(0.02, 0.12, rings);
	vec2 wash = p - motion / surface_size.y;
	float waves = 0.5 + 0.5 * sin(wash.x * 3.4 + sin(wash.y * 2.8));
	vec3 tone = mix(vec3(0.36,0.58,0.56),vec3(0.78,0.51,0.39),waves);
	float vignette = smoothstep(0.85,0.1,length(UV - 0.5));
	vec3 color = mix(paper.rgb, tone, 0.09 + vignette * 0.07);
	color = mix(color, ink.rgb, line * 0.028);
	COLOR = vec4(color, 1.0);
}
