shader_type canvas_item;
void fragment() {
	vec2 extent = 1.0 / TEXTURE_PIXEL_SIZE;
	float radius = min(extent.x, extent.y) * 0.045;
	vec2 q = abs((UV - 0.5) * extent) - extent * 0.5 + radius;
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	COLOR.a *= 1.0 - smoothstep(-1.0, 1.0, distance);
}
