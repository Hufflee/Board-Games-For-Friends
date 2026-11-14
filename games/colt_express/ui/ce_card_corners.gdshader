shader_type canvas_item;
// Скругление углов карт «Кольт Экспресс»: в ассетах угол уже скруглён и залит белым,
// поэтому радиус больше общего hub/card_corners.gdshader (≈7,5 % против 4,5 %) — белые уголки срезаются.
uniform float radius_share = 0.078;
void fragment() {
	vec2 extent = 1.0 / TEXTURE_PIXEL_SIZE;
	float radius = min(extent.x, extent.y) * radius_share;
	vec2 q = abs((UV - 0.5) * extent) - extent * 0.5 + radius;
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	COLOR.a *= 1.0 - smoothstep(-1.0, 1.0, distance);
}
