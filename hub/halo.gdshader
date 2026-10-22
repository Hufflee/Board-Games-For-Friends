shader_type spatial;
// Обводка коробки при наведении: «вывернутая» оболочка со скруглёнными углами и мягким внешним краем.
// Меш — единичная сфера: каждую вершину переносим на поверхность скруглённого параллелепипеда.
render_mode unshaded, cull_front, blend_add, depth_draw_never, shadows_disabled;

uniform vec3 half_size = vec3(0.1);  // половина размера коробки
uniform float margin = 0.007;  // насколько обводка выходит за грани коробки
uniform float radius = 0.022;  // скругление углов и рёбер
uniform vec4 color : source_color = vec4(1.0);
uniform float strength = 0.0;

void vertex() {
	vec3 dir = normalize(VERTEX);
	vec3 a = abs(dir) / half_size;
	vec3 on_box = dir / max(max(a.x, a.y), a.z);  // луч из центра до грани коробки
	vec3 inner = max(half_size + vec3(margin - radius), vec3(0.0));
	vec3 q = clamp(on_box, -inner, inner);
	vec3 d = on_box - q;
	vec3 n = length(d) > 1e-6 ? normalize(d) : dir;
	VERTEX = q + n * radius;
	NORMAL = n;
}

void fragment() {
	// у внешнего силуэта (нормаль поперёк взгляда) — затухание, ближе к коробке — ярче
	float facing = abs(dot(NORMAL, VIEW));
	ALBEDO = color.rgb;
	ALPHA = strength * smoothstep(0.0, 0.25, facing);
}
