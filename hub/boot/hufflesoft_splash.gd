extends Control
## Стартовая анимация HuffleSoft из проекта владельца; finished после5,6с.
signal finished




const WORD:= "hufflesoft"
const FONT:= "res://hub/fonts/hufflesoft_Nunito-Black.ttf"
const TEXT_PX:= 150
const BLUE:= Color(0.22, 0.64, 0.89)
const LIGHT:= Color(0.933, 0.949, 0.969)
const DARK:= Color(0.02, 0.02, 0.03)


const T_REVEAL:= 0.85
const T_REVEALED:= 1.6
const T_BLUE:= 1.85
const T_BURST:= 2.5
const T_BURST_FULL:= 2.95
const T_SETTLE:= 3.6
const T_FADE:= 5.15
const T_END:= 5.6

const WORD_SHADER:= """
shader_type canvas_item;
uniform float grid = 400.0;
uniform float reveal = 1.0;
uniform float wave = 0.0;
uniform float wave_t = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	uv.y += sin(uv.x * 14.0 + wave_t * 9.0) * wave;
	vec2 cells = vec2(grid, grid * 0.25);
	vec2 cell = floor(uv * cells);
	vec2 puv = (cell + 0.5) / cells;
	vec4 c = texture(TEXTURE, grid < 399.0 ? puv : uv);
	float a = c.a;
	if (grid < 399.0) {
		a = step(0.35, a);
		a *= step(h(cell), reveal);
	}
	COLOR = vec4(tint.rgb, a * tint.a);
}
"""

const SWIRL_SHADER:= """
shader_type canvas_item;
uniform float radius = 0.0;
uniform float whiten = 0.0;
uniform float spin = 0.0;
uniform vec2 aspect = vec2(1.7778, 1.0);
vec3 hue(float x) { return clamp(abs(fract(x + vec3(0.0, 2.0, 1.0) / 3.0) * 6.0 - 3.0) - 1.0, 0.0, 1.0); }
void fragment() {
	vec2 p = (UV - 0.5) * aspect;
	float d = length(p);
	float ang = atan(p.y, p.x) / 6.2831853;
	vec3 rainbow = mix(hue(ang + d * 1.6 + spin), vec3(1.0), 0.55 - 0.25 * smoothstep(0.0, 0.6, d));
	vec3 col = mix(rainbow, vec3(0.933, 0.949, 0.969), whiten);
	float inside = 1.0 - smoothstep(radius - 0.02, radius, d);
	COLOR = vec4(col, inside);
}
"""

var _t:= 0.0
var _bg: ColorRect
var _swirl: ColorRect
var _swirl_mat: ShaderMaterial
var _word: TextureRect
var _word_mat: ShaderMaterial
var _word_vp: SubViewport
var _confetti: CPUParticles2D
var _white: ColorRect
var _burst_done:= false
var _chimed := false

func _ready() -> void :
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bg = ColorRect.new()
	_bg.color = DARK
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_swirl = ColorRect.new()
	_swirl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_swirl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swirl_mat = ShaderMaterial.new()
	var ss:= Shader.new()
	ss.code = SWIRL_SHADER
	_swirl_mat.shader = ss
	_swirl.material = _swirl_mat
	add_child(_swirl)


	_word_vp = SubViewport.new()
	_word_vp.transparent_bg = true
	_word_vp.disable_3d = true
	_word_vp.size = Vector2i(1400, 320)
	add_child(_word_vp)
	var lbl:= Label.new()
	lbl.text = WORD
	lbl.add_theme_font_override("font", load(FONT))
	lbl.add_theme_font_size_override("font_size", TEXT_PX)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(_word_vp.size)
	_word_vp.add_child(lbl)

	_word = TextureRect.new()
	_word.texture = _word_vp.get_texture()
	_word.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_word.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_word_mat = ShaderMaterial.new()
	var ws:= Shader.new()
	ws.code = WORD_SHADER
	_word_mat.shader = ws
	_word.material = _word_mat
	add_child(_word)

	_confetti = CPUParticles2D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 160
	_confetti.lifetime = 1.6
	_confetti.explosiveness = 0.95
	_confetti.spread = 180.0
	_confetti.direction = Vector2(0, -1)
	_confetti.initial_velocity_min = 220.0
	_confetti.initial_velocity_max = 900.0
	_confetti.gravity = Vector2(0, 260)
	_confetti.damping_min = 60.0
	_confetti.damping_max = 140.0
	_confetti.scale_amount_min = 3.0
	_confetti.scale_amount_max = 7.0
	var ramp:= Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	_confetti.color_ramp = ramp
	var hues:= Gradient.new()
	hues.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	hues.colors = PackedColorArray([Color("ff6b6b"), Color("ffd93d"), Color("6bcB77"),
		Color("4d96ff"), Color("b388eb"), Color("ff8fab")])
	_confetti.color_initial_ramp = hues
	_confetti.visible = false
	add_child(_confetti)

	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_white)
	resized.connect(_layout)
	_layout()
	_apply(0.0)

func _layout() -> void :
	var w:= size if size.x > 0.0 else get_viewport_rect().size
	var h:= w.y * 0.3
	_word.size = Vector2(w.x * 0.8, h)
	_word.position = Vector2(w.x * 0.1, w.y * 0.5 - h * 0.5)
	_confetti.position = w * 0.5
	_swirl_mat.set_shader_parameter("aspect", Vector2(w.x / maxf(w.y, 1.0), 1.0))

func _process(delta: float) -> void :
	_t += delta
	_apply(_t)
	if _t >= T_REVEALED and not _chimed:
		_chimed = true
		Sfx.play("hufflesoft", -8.0, 0.0)
	if _t >= T_END:
		set_process(false)
		finished.emit()

static func _k(t: float, a: float, b: float) -> float:
	return clampf((t - a) / maxf(b - a, 0.0001), 0.0, 1.0)

func _apply(t: float) -> void :

	_word.visible = t >= T_REVEAL
	_swirl.visible = t >= T_BURST
	var r:= _k(t, T_REVEAL, T_REVEALED)
	_word_mat.set_shader_parameter("reveal", 0.0 if t < T_REVEAL else lerpf(0.15, 1.0, r))
	_word_mat.set_shader_parameter("grid", 400.0 if r >= 1.0 else lerpf(14.0, 140.0, r * r))
	var blue:= _k(t, T_REVEALED - 0.1, T_BLUE)
	var tint:= Color.WHITE.lerp(BLUE, blue)
	tint.a = 1.0 - _k(t, T_FADE, T_END) * 0.85
	_word_mat.set_shader_parameter("tint", tint)

	var wave:= 0.0
	if t >= T_BURST:
		wave = 0.045 * (1.0 - _k(t, T_BURST, T_SETTLE))
	_word_mat.set_shader_parameter("wave", wave)
	_word_mat.set_shader_parameter("wave_t", t)

	var grow:= _k(t, T_BURST, T_BURST_FULL)
	_swirl_mat.set_shader_parameter("radius", 0.0 if t < T_BURST else lerpf(0.05, 1.4, 1.0 - pow(1.0 - grow, 3.0)))
	_swirl_mat.set_shader_parameter("whiten", _k(t, T_BURST + 0.25, T_SETTLE - 0.3))
	_swirl_mat.set_shader_parameter("spin", t * 0.35)
	if t >= T_BURST and not _burst_done:
		_burst_done = true
		_confetti.visible = true
		_confetti.restart()
		_confetti.emitting = true
	if t >= T_SETTLE:
		_bg.color = LIGHT
	_white.color.a = _k(t, T_FADE, T_END)
