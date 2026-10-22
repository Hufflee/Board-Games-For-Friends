shader_type canvas_item;
// Пол таверны (доски), тёплый свет свечей, овальный стол: дерево, кожа, сукно.

uniform sampler2D planks : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D wood : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D leather : source_color, repeat_enable, filter_linear_mipmap;
uniform vec2 rect_size = vec2(1280.0, 720.0);
uniform bool show_table = true;
uniform vec2 table_center = vec2(640.0, 300.0);
uniform vec2 table_radii = vec2(600.0, 255.0);
uniform float rim_width = 34.0;
uniform float leather_width = 10.0;
uniform vec3 felt_color : source_color = vec3(0.09, 0.36, 0.22);
// «Перудо»: пиратский стол — карта сокровищ вместо сукна, канат вместо кожаной окантовки
uniform bool pirate = false;

// хеш без sin(): на больших координатах sin теряет точность и даёт «квадратные» артефакты
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}



float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// плавный многослойный шум (с поворотом слоёв — без сетки)
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = rot * p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

// Приближённое расстояние в пикселях до эллипса (отрицательное — внутри).
float ellipse_dist(vec2 p, vec2 c, vec2 r) {
	vec2 q = (p - c) / r;
	float k = length(q);
	return (k - 1.0) * length(q * r) / max(k, 0.0001);
}

void fragment() {
	vec2 p = UV * rect_size;
	float t = TIME;

	// --- пол ---
	vec3 floor_col = texture(planks, p / 420.0).rgb;
	floor_col *= vec3(1.0, 0.82, 0.62) * 0.55;
	float flicker = 0.94 + 0.04 * sin(t * 7.3) + 0.02 * sin(t * 13.1 + 1.7);
	float pool = 1.0 - smoothstep(150.0, 900.0, length((p - table_center) * vec2(0.85, 1.25)));
	vec3 col = floor_col * (0.35 + 0.95 * pool * flicker);
	// виньетка
	vec2 vuv = UV - 0.5;
	col *= 1.0 - dot(vuv, vuv) * 1.3;

	if (show_table) {
		float d = ellipse_dist(p, table_center, table_radii);
		// тень стола на полу
		float shadow = 1.0 - smoothstep(-10.0, 55.0, ellipse_dist(p, table_center + vec2(0.0, 18.0), table_radii));
		col *= 1.0 - 0.6 * shadow;

		float aa = 1.5;
		float in_table = 1.0 - smoothstep(-aa, aa, d);
		// деревянный бортик с объёмом
		float rim_t = clamp(-d / rim_width, 0.0, 1.0);
		vec3 rim = texture(wood, p / 300.0).rgb * vec3(1.05, 0.85, 0.7);
		float bevel = sin(rim_t * 3.14159);
		vec2 dir = normalize(p - table_center + vec2(0.0001));
		float lightside = 0.5 - 0.5 * dir.y;
		rim *= 0.55 + 0.75 * bevel * (0.6 + 0.6 * lightside);
		vec3 table_col = rim;

		// кожаная окантовка
		float d2 = d + rim_width;
		float in_leather = 1.0 - smoothstep(-aa, aa, d2);
		vec3 leather_col = texture(leather, p / 160.0).rgb * vec3(0.55, 0.32, 0.22);
		leather_col *= 0.8 + 0.4 * sin(clamp(-d2 / leather_width, 0.0, 1.0) * 3.14159);
		if (pirate) {
			// витой канат: косые пряди вдоль бортика
			float ang = atan(dir.y, dir.x);
			float strand = sin(ang * 260.0 + d2 * 0.9);
			leather_col = vec3(0.74, 0.6, 0.38) * (0.6 + 0.3 * strand) * (0.75 + 0.35 * sin(clamp(-d2 / leather_width, 0.0, 1.0) * 3.14159));
		}
		table_col = mix(table_col, leather_col, in_leather);

		// сукно
		float d3 = d2 + leather_width;
		float in_felt = 1.0 - smoothstep(-aa, aa, d3);
		float n = noise(p * 0.9) * 0.5 + noise(p * 0.23) * 0.5;
		vec3 felt = felt_color * (0.88 + 0.22 * n);
		float center_light = 1.0 - smoothstep(0.0, 1.0, length((p - table_center) / (table_radii * 1.05)));
		felt *= 0.7 + 0.55 * center_light * flicker;
		felt *= 0.55 + 0.45 * smoothstep(0.0, 28.0, -d3);  // тень у бортика
		if (pirate) {
			// старый пергамент: пятна, потёртости, обожжённый край
			float n2 = fbm(p * 0.012);
			float speck = fbm(p * 0.09) * 0.12;
			n2 = clamp(n2 * 1.3 - 0.15 + speck - 0.06, 0.0, 1.0);
			vec3 parch = mix(vec3(0.62, 0.48, 0.3), vec3(0.86, 0.75, 0.55), n2);
			parch *= 0.75 + 0.4 * center_light * flicker;
			parch = mix(vec3(0.25, 0.14, 0.06), parch, smoothstep(0.0, 34.0, -d3 + fbm(p * 0.03) * 26.0));
			felt = parch;
		}
		// тонкая золотая линия по сукну
		float line = 1.0 - smoothstep(0.0, 1.6, abs(d3 + 26.0));
		felt = mix(felt, pirate ? vec3(0.3, 0.17, 0.08) : vec3(0.85, 0.7, 0.35) * 0.8, line * 0.55);
		table_col = mix(table_col, felt, in_felt);

		col = mix(col, table_col, in_table);
	}
	COLOR = vec4(col, 1.0);
}
