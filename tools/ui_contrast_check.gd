## Измеряет контраст палитр без записи настроек.
## Запуск: --headless --audio-driver Dummy --script res://tools/ui_contrast_check.gd.
extends SceneTree

const Contrast = preload("res://hub/ui_contrast.gd")
const STYLES := [
	["res://games/the_mind/ui/tm_style.gd", false],
	["res://games/poker/ui/pk_style.gd", true],
	["res://games/king_of_12/ui/ui_kit.gd", true],
	["res://games/colt_express/ui/ce_style.gd", false],
	["res://games/ready_set_bet/ui/rsb_style.gd", false],
	["res://games/hues_and_cues/ui/hc_style.gd", false],
	["res://games/brodilka/ui/br_style.gd", false],
	["res://games/phantom_ink/ui/pi_style.gd", true],
	["res://games/gloom/ui/gl_style.gd", true],
	["res://games/four_souls/ui/fs_style.gd", true],
	["res://games/machi_koro/ui/mk_style.gd", false],
	["res://games/first_contact/ui/fc_style.gd", false],
	["res://games/green_team_wins/ui/gtw_style.gd", false],
	["res://games/in_broad_strokes/ui/ibs_style.gd", false],
	["res://games/stillion/ui/st_style.gd", false],
	["res://games/things_in_rings/ui/tr_style.gd", false],
	["res://games/tip_top/ui/tt_style.gd", true],
	["res://games/not_a_hat/ui/nh_style.gd", true],
	["res://games/dangerous_words/ui/dw_style.gd", true],
	["res://games/khorom/ui/kh_style.gd", false],
	["res://games/the_gang/ui/tg_style.gd", true],
	["res://games/blood_on_the_clocktower/ui/bc_style.gd", false],
	["res://games/custom/ui/cg_style.gd", false],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var prefs := root.get_node("Prefs")
	var saved: String = prefs.theme_mode
	var failures := 0
	var total := 0
	for entry: Array in STYLES:
		var style: GDScript = load(entry[0])
		var themes := ["dark"] if entry[1] else ["light", "dark"]
		for mode: String in themes:
			prefs.theme_mode = mode
			if style.has_method("sync_prefs"):
				style.sync_prefs()
			for pair: Array in style.contrast_pairs():
				var ratio := Contrast.ratio(pair[0], pair[1])
				var threshold := 3.0 if pair[3] else 4.5
				var passed := ratio >= threshold
				total += 1
				if not passed:
					failures += 1
				print("%s [%s] %s: %.2f:1 (порог %.1f)%s" % [
					str(entry[0]).get_file(), mode, pair[2], ratio, threshold, "" if passed else " — ниже порога"])
	prefs.theme_mode = saved
	print("Проверок: %d, ошибок: %d" % [total, failures])
	quit(0 if failures == 0 else 1)
