shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec2 source_uv;
uniform vec2 center_uv;
uniform float radius = 144.0;
void fragment() {
	float distance_px = length((SCREEN_UV - center_uv) * viewport_size);
	float mask = 1.0 - smoothstep(radius - 1.5, radius, distance_px);
	vec2 sample_uv = clamp(source_uv + (SCREEN_UV - center_uv) / 2.0, vec2(0.0), vec2(1.0));
	vec3 scene = texture(screen_tex, sample_uv).rgb;
	float rim = smoothstep(radius - 4.0, radius - 2.0, distance_px);
	COLOR = vec4(mix(scene, vec3(0.36, 0.72, 0.72), rim), mask);
}
