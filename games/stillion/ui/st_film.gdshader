shader_type canvas_item;
render_mode unshaded;

// Мелкая живая рябь по видео-референсу: зерно обновляется как кадры плёнки.
// Размер зерна — в пикселях окна, а не фиксированное разрешение 1280×720.
uniform float strength : hint_range(0.0, 2.0) = 1.0;
uniform float grain_amount : hint_range(0.0, 0.15) = 0.12;
uniform float grain_pixels : hint_range(0.75, 3.0) = 1.15;
uniform float film_fps : hint_range(12.0, 60.0) = 24.0;
uniform float flicker_amount : hint_range(0.0, 0.03) = 0.004;
uniform float ripple_amount : hint_range(0.0, 0.03) = 0.0102;
uniform float vignette_amount : hint_range(0.0, 0.3) = 0.08;
uniform float dust_amount : hint_range(0.0, 0.15) = 0.05;
// Отрицательное значение — живое время; положительное удобно для проверки кадров.
uniform float preview_time = -1.0;

float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	float time = preview_time < 0.0 ? TIME : preview_time;
	float frame = floor(time * film_fps);
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 cell = floor(pixel / grain_pixels);
	float fine = hash21(cell + vec2(frame * 47.0, frame * 19.0)) - 0.5;
	float soft = hash21(floor(pixel / 3.0) + vec2(frame * 13.0, frame * 31.0)) - 0.5;
	float grain = (fine * 0.85 + soft * 0.15) * grain_amount;
	float flicker = (hash21(vec2(frame, 7.0)) - 0.5) * flicker_amount;
	float ripple = sin(pixel.y * 0.048 - time * 5.2) * ripple_amount * 0.5;
	vec2 edge = (SCREEN_UV - 0.5) * 1.4142;
	float vignette = smoothstep(0.3, 0.95, dot(edge, edge)) * vignette_amount;
	// Редкие маленькие пылинки меняются вместе с плёнкой, без полос во всю высоту.
	vec2 dust_cell = floor(pixel / 96.0);
	vec2 spot = vec2(hash21(dust_cell + frame), hash21(dust_cell + frame + 71.0));
	float distance_px = length(fract(pixel / 96.0) * 96.0 - spot * 96.0);
	float dust = (1.0 - smoothstep(0.4, 1.7, distance_px));
	dust *= step(0.975, hash21(dust_cell + frame + 123.0)) * dust_amount;
	float exposure = grain + flicker + ripple - vignette - dust;
	// Положительное зерно осветляет, отрицательное затемняет: нет постоянной бурой пелены.
	COLOR = vec4(vec3(step(0.0, exposure)), clamp(abs(exposure) * strength, 0.0, 0.35));
}
