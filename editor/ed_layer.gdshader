shader_type canvas_item;
// Неразрушающая коррекция слоя: исходный импорт остаётся неизменным.
uniform float brightness = 0.0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform float exposure = 0.0;
uniform float hue = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	vec4 source = COLOR;
	vec3 rgb = source.rgb * exp2(exposure);
	float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	rgb = mix(vec3(luminance), rgb, saturation);
	float c = cos(hue);
	float s = sin(hue);
	vec3 axis = normalize(vec3(1.0));
	rgb = rgb * c + cross(axis, rgb) * s + axis * dot(axis, rgb) * (1.0 - c);
	rgb = (rgb - 0.5) * contrast + 0.5 + brightness;
	COLOR = vec4(clamp(rgb * tint.rgb, vec3(0.0), vec3(1.0)), source.a);
}
