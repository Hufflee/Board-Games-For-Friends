// Маска аватара по координатам слота: одинаковое скругление после обрезки cover.
shader_type canvas_item;

uniform vec2 slot_size = vec2(64.0);
uniform float radius = 10.0;  // = внутренний радиус рамки (VictoryScreen._avatar_box)
varying vec2 slot_point;

void vertex() {
	slot_point = VERTEX;
}

void fragment() {
	vec2 edge = abs(slot_point - slot_size * 0.5) - slot_size * 0.5 + vec2(radius);
	float distance_to_edge = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - radius;
	COLOR.a *= 1.0 - smoothstep(-0.75, 0.75, distance_to_edge);
}
