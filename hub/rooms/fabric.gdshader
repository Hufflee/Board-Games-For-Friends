shader_type spatial;
// Плоская «лоу-поли» заливка для украшений зимней комнаты (hub/rooms/winter_decor.gd): колпаки, кассеты.
// Цветной свет комнаты не учитывается (голубой экран иначе делал красные грани чёрными) — каждая грань
// берёт одну из трёх ступеней яркости от условного света сверху-слева, как в 2D-рисунке.
// Нарисованные в текстуре тени складок остаются как есть.
render_mode unshaded, cull_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float brightness = 0.7;
uniform vec3 light_dir = vec3(-0.35, 0.85, 0.45);  // условный свет (в координатах мира)
uniform float shade_low = 0.0;  // нарисованная тень снизу: 0 — нет, 1 — низ чёрный
uniform float half_height = 0.1;  // полувысота предмета (м) для тени снизу
uniform int bands = 3;  // ступеней яркости: больше — соседние грани разного оттенка

varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(FRONT_FACING ? NORMAL : -NORMAL, 0.0)).xyz);
	float l = dot(n, normalize(light_dir));
	float band = l > 0.45 ? 1.0 : (l > -0.1 ? 0.78 : 0.6);
	if (bands > 3) {
		float k = floor(clamp(l * 0.5 + 0.5, 0.0, 0.999) * float(bands)) / float(bands - 1);
		band = mix(0.4, 1.15, k);  // заметнее: соседние грани складки — явно разные оттенки
	}
	// снизу — две ступени тени, как нарисованные
	float h = clamp(local_y / half_height * 0.5 + 0.5, 0.0, 1.0);
	float low = h < 0.22 ? 1.0 : (h < 0.5 ? 0.5 : 0.0);
	band *= 1.0 - shade_low * low;
	ALBEDO = texture(tex, UV).rgb * tint.rgb * band * brightness;
}
