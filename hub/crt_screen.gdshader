shader_type spatial;
// Экран ЭЛТ-телевизора: картинка экрана (SubViewport) через три эффекта кинескопа —
// изгиб (barrel) с тёмными закруглёнными краями, разъезд цветовых каналов с мягким свечением (chroma bleed)
// и строки развёртки с медленной «прокаткой» и мерцанием. Плюс выпуклое стекло, виньетка и блик.
render_mode unshaded, cull_back;

uniform sampler2D screen_tex : source_color, filter_linear, repeat_disable;  // содержимое экрана (надписи)
uniform vec4 base_color : source_color = vec4(0.04, 0.55, 0.75, 1.0);
uniform vec4 glow_color : source_color = vec4(0.4, 0.95, 1.0, 1.0);
uniform float bulge = 0.012;
uniform float brightness = 1.4;
uniform float curvature = 0.0;  // сила изгиба картинки (0 — ровная; форму экрана задаёт corner)
uniform float chroma = 0.006;  // разъезд каналов (доля ширины экрана)
uniform float bleed = 0.55;  // сила свечения вокруг ярких мест
uniform float corner = 0.07;  // радиус скругления стекла (доля высоты экрана); 0 — прямоугольный экран
uniform float edge_fade = 0.05;  // ширина мягкого затухания картинки к краю стекла (доля высоты)
uniform float aspect = 1.342;  // ширина / высота стекла (0.51 × 0.38; ставит neon_room.gd)
uniform float lines = 96.0;  // сколько строк развёртки на высоту экрана (больше — муар на маленьком экране)

void vertex() {
	vec2 c = UV * 2.0 - 1.0;
	VERTEX.z += bulge * (1.0 - c.x * c.x) * (1.0 - c.y * c.y);
}

// бочкообразный изгиб: края картинки уходят от центра
vec2 barrel(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	c *= 1.0 + curvature * dot(c, c) * 0.5;
	return c * 0.5 + 0.5;
}

// содержимое экрана с фоном кинескопа: градиент + надписи поверх
vec3 picture(vec2 uv) {
	vec2 c = uv * 2.0 - 1.0;
	vec3 bg = mix(base_color.rgb, glow_color.rgb, smoothstep(0.9, 0.0, length(c)) * 0.45);
	vec4 t = texture(screen_tex, uv);
	return mix(bg, t.rgb, t.a);
}

void fragment() {
	vec2 uv = barrel(UV);
	// стекло — скруглённый прямоугольник: картинка заполняет его до края, за скруглением видна рамка корпуса
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	vec2 half_size = vec2(aspect, 1.0) * 0.5 - corner;
	vec2 q = abs(p) - half_size;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;  // расстояние до края (внутри — отрицательное)
	// углы за скруглением вырезаем совсем (а не делаем прозрачными): прозрачное стекло писало бы глубину,
	// и затенение/отражения рисовали бы рамку под ним светлее — резкая граница по краю стекла
	if (d > 0.0) {
		discard;
	}
	// chroma bleed: красный уходит вправо, синий влево; к краям экрана разъезд сильнее
	vec2 c = uv * 2.0 - 1.0;
	vec2 off = vec2(chroma * (0.6 + 0.6 * length(c)), 0.0);
	vec3 col;
	col.r = picture(uv + off).r;
	col.g = picture(uv).g;
	col.b = picture(uv - off).b;
	// свечение: размытая копия ярких мест (несколько выборок по кругу), тоже с разъездом
	vec3 glow = vec3(0.0);
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.785398;
		vec2 d = vec2(cos(a), sin(a)) * 0.018;
		vec4 t = texture(screen_tex, uv + d + off * 1.5);
		glow += t.rgb * t.a;
	}
	col += glow / 8.0 * bleed;
	// строки развёртки: тонкие тёмные полосы, медленно катятся вниз, лёгкое мерцание
	float scan = 0.78 + 0.22 * pow(0.5 + 0.5 * sin((uv.y * lines + TIME * 2.2) * 6.2832), 1.4);
	float roll = 0.95 + 0.05 * sin(uv.y * 7.0 - TIME * 2.6);
	float flicker = 0.975 + 0.025 * sin(TIME * 37.0);
	col *= scan * roll * flicker;
	// виньетка к закруглённым краям
	// виньетка мягкая: края темнее, но не чёрные
	float vign = mix(0.62, 1.0, smoothstep(1.5, 0.45, length(c * vec2(0.95, 1.05))));
	col *= vign * brightness;
	// у самого края стекла картинка плавно гаснет почти до цвета рамки — без резкой границы
	float fade = smoothstep(0.0, edge_fade, -d);
	col *= mix(0.12, 1.0, fade * fade * (3.0 - 2.0 * fade));
	// блик на стекле (по самому стеклу, без изгиба)
	vec2 g = UV * 2.0 - 1.0;
	col += vec3(smoothstep(0.35, 0.0, length(g - vec2(-0.45, 0.5))) * 0.3);
	ALBEDO = col;
}
