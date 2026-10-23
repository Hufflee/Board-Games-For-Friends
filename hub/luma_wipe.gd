class_name LumaWipe
extends CanvasLayer
## Переход «luma wipe» (matte wipe): снимок старого экрана лежит поверх новой сцены, на нём проступает
## мягкая облачная маска, и в самых тёмных её местах прорезаются маленькие пятна — сквозь них видна новая сцена.
## Пятна плавно растут, сливаются, и старый экран исчезает целиком; сам он при этом всё сильнее размывается.
## Пока новая сцена грузится в фоне (load_threaded_request), снимок плавно размывается и на нём проступает
## облачная тень маски; как загрузилась — смена сцены и сами пятна.
## Запуск: LumaWipe.change_scene(path) вместо change_scene_to_file (сейчас — только старт игры из хаба).

const DURATION := 1.9  # пятна: от первых точек до полного перехода, с
const PREP := 0.45  # минимум на размытие до пятен, с (если сцена загрузится раньше)
const SHADER := """
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D old_screen : filter_linear_mipmap;
uniform float progress = 0.0;  // пятна: 0 — старый экран целиком, 1 — новая сцена
uniform float soft = 0.0;  // размытие и тень маски на старом экране, 0…1
uniform float aspect = 1.7778;
uniform float seed = 0.0;

// хеш без синуса (Dave Hoskins) — без полос и сетки
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031 + seed);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// градиентный шум: мягкие округлые пятна, без «кубиков» value noise
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash(i) * 6.2832;
	float b = hash(i + vec2(1.0, 0.0)) * 6.2832;
	float c = hash(i + vec2(0.0, 1.0)) * 6.2832;
	float d = hash(i + vec2(1.0, 1.0)) * 6.2832;
	float va = dot(vec2(cos(a), sin(a)), f);
	float vb = dot(vec2(cos(b), sin(b)), f - vec2(1.0, 0.0));
	float vc = dot(vec2(cos(c), sin(c)), f - vec2(0.0, 1.0));
	float vd = dot(vec2(cos(d), sin(d)), f - vec2(1.0, 1.0));
	return mix(mix(va, vb, u.x), mix(vc, vd, u.x), u.y) * 0.5 + 0.5;
}

// облачная маска: октавы с поворотом — края пятен рваные, но не по сетке
float fbm(vec2 p) {
	mat2 rot = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	float v = 0.0;
	float a = 0.6;
	for (int k = 0; k < 4; k++) {
		v += a * gnoise(p);
		p = rot * p + vec2(5.2, 1.3);
		a *= 0.45;
	}
	return v / 1.05;
}

void fragment() {
	vec2 uv = UV;
	vec2 q = vec2(uv.x * aspect, uv.y) * 2.2;
	// маска чуть «дышит» — пятна растут не по линейке, а живо
	float m = fbm(q + vec2(progress * 0.35, -progress * 0.2));
	m = clamp((m - 0.28) / 0.5, 0.0, 1.0);
	// порог идёт от самых тёмных точек маски к самым светлым
	float t = progress * 1.14 - 0.08;  // при 0 дыр нет совсем
	float edge = 0.05 + 0.6 * fwidth(m);  // мягкий край, сглаженный по пикселю
	float keep = smoothstep(t - edge, t + edge, m);  // 1 — старый экран, 0 — дыра в новую сцену
	// старый экран всё сильнее размыт (мип-уровни снимка)
	float blur = soft * 4.5;
	vec3 col = textureLod(old_screen, uv, blur).rgb;
	// облачная маска проступает на старом экране лёгкой тенью
	float veil = soft * (1.0 - m) * 0.35;
	col = mix(col, col * 0.55, veil);
	// тонкая светлая кайма по краю пятен — край читается, но не кричит
	float rim = (1.0 - abs(keep * 2.0 - 1.0)) * smoothstep(0.0, 0.15, progress) * (1.0 - smoothstep(0.85, 1.0, progress));
	col += vec3(0.9, 0.85, 1.0) * rim * 0.18;
	COLOR = vec4(col, keep);
}
"""

var _rect: TextureRect
var _path := ""
var _prep := 0.0  # сколько уже размываем, с
var _soft := 0.0
var _t := -1.0  # время пятен, с; -1 — сцена ещё не сменилась


## Снять текущий кадр, загрузить сцену в фоне, сменить её и проявить сквозь пятна.
static func change_scene(path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var img := tree.root.get_viewport().get_texture().get_image()
	img.generate_mipmaps()
	var w := LumaWipe.new()
	w.layer = 120
	w._path = path
	tree.root.add_child(w)
	w._setup(ImageTexture.create_from_image(img), tree.root.get_visible_rect().size)
	ResourceLoader.load_threaded_request(path)


func _setup(tex: Texture2D, vs: Vector2) -> void:
	_rect = TextureRect.new()
	_rect.texture = tex
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # пока идёт переход, клики не уходят в сцены
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mat.set_shader_parameter("old_screen", tex)
	mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	mat.set_shader_parameter("seed", randf())
	_rect.material = mat
	add_child(_rect)


func _process(delta: float) -> void:
	var mat := _rect.material as ShaderMaterial
	# размытие нарастает всё время перехода (быстро в начале, мягко к концу)
	_prep += delta
	_soft = minf(1.0, _soft + delta / 1.2)
	mat.set_shader_parameter("soft", 1.0 - pow(1.0 - _soft, 2.0))
	if _t < 0.0:
		if _path == "":
			return
		var st := ResourceLoader.load_threaded_get_status(_path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or _prep < PREP:
			return
		var path := _path
		_path = ""
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(path))
		else:
			get_tree().change_scene_to_file(path)  # фоновая загрузка не вышла — по-простому
		# новая сцена строится кадр-другой — пятна начинаем, когда она уже на экране
		await get_tree().process_frame
		await get_tree().process_frame
		_t = 0.0
		return
	_t += delta
	var k := clampf(_t / DURATION, 0.0, 1.0)
	# мягкий старт и плавное дотягивание (синусоида), без рывков
	mat.set_shader_parameter("progress", 0.5 - 0.5 * cos(k * PI))
	if k >= 1.0:
		queue_free()
