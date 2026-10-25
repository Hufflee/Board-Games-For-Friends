shader_type canvas_item;
uniform sampler2D angry_sheet : source_color, filter_linear;
uniform vec4 region;
uniform vec4 previous_region;
uniform float turn_blend = 1.0;
uniform float anger = 0.0;
uniform float pressure = 0.0;
uniform float heat = 0.0;
uniform float recoil = 0.0;
uniform float breath = 0.0;
uniform vec2 direction = vec2(1.0, 0.0);

vec4 cell(sampler2D neutral_sheet, vec4 area, vec2 local) {
	vec2 uv = area.xy + local * area.zw;
	vec4 neutral = texture(neutral_sheet, uv);
	vec4 angry = texture(angry_sheet, uv);
	return mix(neutral, angry, anger);
}

void fragment() {
	// Верх корпуса дышит и растёт, основание остаётся на земле.
	vec2 local = (UV - 0.5) * 1.36 + 0.5;
	float barrel = 1.0 - smoothstep(0.58, 0.88, local.y);
	vec2 center = vec2(0.5, 0.6);
	local = center + (local - center) / vec2(1.0 + barrel * pressure * 0.13, 1.0 + barrel * (pressure * 0.18 + breath));
	local += direction * recoil * barrel * 0.045;
	vec4 paint = cell(TEXTURE, region, local);
	float lightness = dot(paint.rgb, vec3(0.2126, 0.7152, 0.0722));
	// Белки глаз и светлые блики сохраняются, угольный ствол становится почти красным.
	float body = smoothstep(0.025, 0.11, lightness) * (1.0 - smoothstep(0.38, 0.67, lightness)) * barrel;
	vec3 hot = vec3(0.78, 0.045, 0.025) * (0.45 + lightness);
	paint.rgb = mix(paint.rgb, hot, body * pow(clamp(heat, 0.0, 1.0), 1.3) * 0.98);
	float inside = step(0.0, local.x) * step(local.x, 1.0) * step(0.0, local.y) * step(local.y, 1.0);
	COLOR = paint * vec4(1.0, 1.0, 1.0, inside);
}
