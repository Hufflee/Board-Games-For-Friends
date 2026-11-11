shader_type spatial;
render_mode unshaded;

uniform sampler2D wash_texture : source_color, filter_linear, repeat_disable;
uniform vec4 silhouettes[16];
uniform int silhouette_count = 0;
uniform bool shelf_wall = true;

varying vec3 room_position;

void vertex() {
	room_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 wash = texture(wash_texture, UV);
	float shadow = 0.0;
	if (shelf_wall) {
		for (int i = 0; i < silhouette_count; i++) {
			vec4 item = silhouettes[i];
			float up = max(0.0, room_position.y - item.y);
			float spread = 0.017 + up * 0.19;
			float sides = 1.0 - smoothstep(item.z * 0.38, item.z * 0.5 + spread, abs(room_position.z - item.x));
			float top = 1.0 - smoothstep(item.w * 0.88, item.w + spread, up);
			shadow = max(shadow, sides * top);
		}
	}
	ALBEDO = wash.rgb;
	ALPHA = wash.a * (1.0 - 0.77 * shadow);
}
