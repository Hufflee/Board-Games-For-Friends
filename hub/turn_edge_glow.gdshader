shader_type canvas_item;
render_mode unshaded;
// Неоновая рамка «твой ход»: свечение от краёв экрана внутрь, яркость задаёт скрипт.
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform float radius = 56.0;
uniform float strength = 0.4;
uniform vec4 glow_color : source_color = vec4(0.2, 0.6, 1.0, 1.0);

void fragment() {
	vec2 p = UV * rect_size;
	float d = min(min(p.x, rect_size.x - p.x), min(p.y, rect_size.y - p.y));
	// тонкая яркая линия у самого края и мягкий ореол дальше
	float line = exp(-d / 3.0) * 0.55;
	float halo = exp(-d / (radius * 0.45)) * 0.55;
	float a = clamp(line + halo, 0.0, 1.0) * strength;
	COLOR = vec4(mix(glow_color.rgb, vec3(1.0), line * 0.35), a);
}
