extends RefCounted
## Общие частицы конфетти для победы и попадания в корзину.

static func make(accent: Color) -> CPUParticles2D:
	var conf := CPUParticles2D.new()
	conf.name = "Confetti"
	conf.one_shot = true
	conf.gravity = Vector2(0, 240)
	conf.initial_velocity_min = 60.0
	conf.initial_velocity_max = 200.0
	conf.angular_velocity_min = -360.0
	conf.angular_velocity_max = 360.0
	conf.scale_amount_min = 4.0
	conf.scale_amount_max = 8.0
	var hues := Gradient.new()
	hues.set_color(0, accent.lightened(0.3))
	hues.set_color(1, Color("5fb4ef"))
	hues.add_point(0.33, Color("e2645c"))
	hues.add_point(0.66, Color("6fcf6f"))
	conf.color_initial_ramp = hues
	conf.emitting = false
	return conf


static func start(conf: CPUParticles2D) -> void:
	conf.emitting = true
	conf.get_tree().create_timer(conf.lifetime + 1.5).timeout.connect(_free.bind(weakref(conf)))


static func _free(reference: WeakRef) -> void:
	var conf: Node = reference.get_ref()
	if is_instance_valid(conf):
		conf.queue_free()
