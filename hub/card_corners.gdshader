shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.0);
uniform float outline_width : hint_range(0.0, 4.0) = 0.0;

void fragment() {
	vec2 extent = 1.0 / TEXTURE_PIXEL_SIZE;
	float radius = min(extent.x, extent.y) * 0.045;
	vec2 q = abs((UV - 0.5) * extent) - extent * 0.5 + radius;
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
	if (outline_width > 0.0) {
		float pixel = length(vec2(dFdx(distance), dFdy(distance)));
		float outline = smoothstep(-outline_width * pixel - 0.5 * pixel, -outline_width * pixel + 0.5 * pixel, distance);
		COLOR.rgb = mix(COLOR.rgb, outline_color.rgb, outline * outline_color.a);
	}
	COLOR.a *= 1.0 - smoothstep(-1.0, 1.0, distance);
}
