shader_type canvas_item;
uniform sampler2D blink_sheet : source_color, filter_linear;
uniform vec2 cell;
uniform vec4 eyes;
uniform float blink = 0.0;
uniform float breath = 0.0;
uniform float sway = 0.0;
uniform bool candle = false;
uniform float flicker = 0.0;

varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

void fragment() {
	vec2 local = (UV - 0.5) * 1.12 + 0.5;
	local.y = 0.97 + (local.y - 0.97) / (1.0 + breath);
	local.x += sway * pow(max(0.0, 1.0 - local.y), 2.0);
	vec2 uv = (cell + local) / vec2(4.0, 2.0);
	vec4 paint = texture(TEXTURE, uv);
	vec4 closed = texture(blink_sheet, uv);
	vec2 eye_local = (local - eyes.xy) / eyes.zw;
	float eye_mask = smoothstep(0.0, 0.07, eye_local.x) * smoothstep(0.0, 0.07, eye_local.y);
	eye_mask *= (1.0 - smoothstep(0.93, 1.0, eye_local.x)) * (1.0 - smoothstep(0.93, 1.0, eye_local.y));
	paint = mix(paint, closed, blink * eye_mask);
	if (candle) {
		paint.rgb *= 1.0 + flicker * (1.0 - smoothstep(0.1, 0.25, local.y));
	}
	float inside = step(0.0, local.x) * step(local.x, 1.0) * step(0.0, local.y) * step(local.y, 1.0);
	COLOR = paint * vertex_tint * vec4(1.0, 1.0, 1.0, inside);
}
