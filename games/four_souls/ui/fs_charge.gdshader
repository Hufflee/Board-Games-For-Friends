shader_type canvas_item;
// Карта с зарядом: скруглённые углы (как hub/card_corners) + чёрно-белый фильтр, пока карта разряжена.
// gray: 0 — цветная (заряжена), 1 — ч/б (разряжена); стол плавно меняет его при зарядке.
uniform float gray : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 extent = 1.0 / TEXTURE_PIXEL_SIZE;
	float radius = min(extent.x, extent.y) * 0.045;
	vec2 q = abs((UV - 0.5) * extent) - extent * 0.5 + radius;
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	float luma = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	COLOR.rgb = mix(COLOR.rgb, vec3(luma) * 0.82, gray);  // ч/б и чуть темнее — «повёрнута»
	COLOR.a *= 1.0 - smoothstep(-1.0, 1.0, distance);
}
