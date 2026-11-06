shader_type spatial;
// Стикер хаба (hub/game_box.gd, hub/sticker_board.gd): картинка с прозрачностью, обрезанная по краю поверхности.
// to_surface — положение квада относительно коробки/доски (постоянное, коробка может лететь);
// всё, что за half_size (в координатах поверхности), не рисуется: торчащий за обложку край не виден.
render_mode depth_prepass_alpha, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform mat4 to_surface = mat4(1.0);
uniform vec3 half_size = vec3(1000.0);
uniform float roughness_value = 0.4;

varying vec3 surface_pos;

void vertex() {
	surface_pos = (to_surface * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (any(greaterThan(abs(surface_pos), half_size))) {
		discard;
	}
	vec4 color = texture(albedo_tex, UV);
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ROUGHNESS = roughness_value;
}
