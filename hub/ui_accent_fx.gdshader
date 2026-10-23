shader_type canvas_item;
render_mode unshaded;
// Общая геометрия: скругления совпадают со StyleBox, блик не выходит за кнопку.
uniform int mode = 0;
uniform vec2 rect_size = vec2(240.0, 48.0);
uniform vec4 corners = vec4(12.0); // слева сверху, справа сверху, справа снизу, слева снизу
uniform float padding = 0.0;
uniform float phase_offset = 0.0;
uniform float opacity = 1.0;
uniform vec2 cursor = vec2(-200.0);
uniform vec4 glow_color : source_color = vec4(0.58, 0.66, 0.85, 1.0);
float rounded_distance(vec2 p) {
	float radius = p.y < 0.0 ? (p.x < 0.0 ? corners.x : corners.y) : (p.x < 0.0 ? corners.w : corners.z);
	radius = min(radius, min(rect_size.x, rect_size.y) * 0.5);
	vec2 q = abs(p) - rect_size * 0.5 + vec2(radius);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}
void fragment() {
	vec2 point = UV * (rect_size + vec2(padding * 2.0)) - vec2(padding);
	float distance_to_edge = rounded_distance(point - rect_size * 0.5);
	float alpha = 0.0;
	vec3 color = vec3(1.0);
	if (mode == 0) {
		// 0.8 секунды движения, затем 4.4 секунды покоя.
		float phase = mod(TIME + phase_offset, 5.2);
		float progress = clamp(phase / 0.8, 0.0, 1.0);
		float width = clamp(rect_size.x * 0.14, 20.0, 64.0);
		float position = mix(-width - rect_size.y * 0.45, rect_size.x + width + rect_size.y * 0.45, progress);
		float band = (point.x + point.y * 0.45 - position) / width;
		float sweep = exp(-band * band * 2.8) * 0.14 + exp(-band * band * 10.0) * 0.08;
		float mask = 1.0 - smoothstep(-1.5, -0.5, distance_to_edge);
		alpha = sweep * mask * (1.0 - step(0.8, phase)) * opacity;
	} else {
		// Узкая линия у края и мягкий ореол, только рядом с курсором.
		float radius = clamp(min(rect_size.x, rect_size.y) * 0.6, 48.0, 90.0);
		vec2 delta = (point - cursor) / radius;
		float hotspot = exp(-dot(delta, delta) * 2.5);
		float line = exp(-pow((distance_to_edge + 0.5) / 1.1, 2.0));
		float halo = exp(-abs(distance_to_edge) / 3.0) * 0.22;
		alpha = clamp(line + halo, 0.0, 1.0) * hotspot * opacity;
		color = mix(glow_color.rgb, vec3(1.0), line * 0.18);
	}
	COLOR = vec4(color, alpha);
}
