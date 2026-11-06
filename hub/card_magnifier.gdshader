shader_type canvas_item;
render_mode unshaded;
// Лупа (hub/card_magnifier.gd). Если под курсором карта — рисуем её из исходной текстуры в полном разрешении
// (card_tex, use_card), иначе — увеличенный кусок экрана, как раньше.
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D card_tex : repeat_disable, filter_linear_mipmap;
uniform vec2 viewport_size = vec2(1280.0, 720.0);
uniform vec2 source_uv;
uniform vec2 center_uv;
uniform float radius = 144.0;
uniform float zoom = 2.0;
uniform bool use_card = false;
uniform vec2 card_uv;  // точка карты под курсором (0..1)
uniform vec2 card_uv_per_px;  // сколько UV карты в одном пикселе лупы
uniform float card_angle = 0.0;  // поворот карты на экране
uniform vec4 card_region = vec4(0.0, 0.0, 1.0, 1.0);  // область AtlasTexture в атласе

void fragment() {
	vec2 offset_px = (SCREEN_UV - center_uv) * viewport_size;
	float distance_px = length(offset_px);
	float mask = 1.0 - smoothstep(radius - 1.5, radius, distance_px);
	vec2 sample_uv = clamp(source_uv + (SCREEN_UV - center_uv) / zoom, vec2(0.0), vec2(1.0));
	vec3 scene = texture(screen_tex, sample_uv).rgb;
	if (use_card) {
		float c = cos(-card_angle);
		float s = sin(-card_angle);
		vec2 local_px = vec2(offset_px.x * c - offset_px.y * s, offset_px.x * s + offset_px.y * c);
		vec2 uv = card_uv + local_px * card_uv_per_px;
		if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
			vec4 card = texture(card_tex, card_region.xy + uv * card_region.zw);
			scene = mix(scene, card.rgb, card.a);
		}
	}
	float rim = smoothstep(radius - 4.0, radius - 2.0, distance_px);
	COLOR = vec4(mix(scene, vec3(0.36, 0.72, 0.72), rim), mask);
}
