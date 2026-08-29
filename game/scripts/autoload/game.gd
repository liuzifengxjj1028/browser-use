extends Node
## Global game state: input registration, settings, save data, noise event bus.

signal noise_emitted(pos: Vector3, radius: float, loudness: float)

const SAVE_PATH := "user://save.json"

var completed_levels: Array = []
var seen_intros: Array = []
var settings := {"lang": "zh", "volume": 0.8}
var smoke_test := false

func _ready() -> void:
	smoke_test = "smoke" in OS.get_cmdline_user_args()
	_register_inputs()
	load_save()
	Loc.set_lang(str(settings.get("lang", "zh")))
	apply_volume()

func emit_noise(pos: Vector3, radius: float, loudness := 1.0) -> void:
	noise_emitted.emit(pos, radius, loudness)

func mark_completed(level_id: String) -> void:
	if level_id not in completed_levels:
		completed_levels.append(level_id)
	save()

func mark_intro_seen(level_id: String) -> void:
	if level_id not in seen_intros:
		seen_intros.append(level_id)
	save()

func set_volume(v: float) -> void:
	settings["volume"] = clampf(v, 0.0, 1.0)
	apply_volume()
	save()

func apply_volume() -> void:
	var v := float(settings.get("volume", 0.8))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.001)))
	AudioServer.set_bus_mute(0, v <= 0.001)

func set_lang(l: String) -> void:
	settings["lang"] = l
	Loc.set_lang(l)
	save()

func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"completed": completed_levels,
		"intros": seen_intros,
		"settings": settings,
	}))

func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		completed_levels = parsed.get("completed", [])
		seen_intros = parsed.get("intros", [])
		var s: Variant = parsed.get("settings", {})
		if s is Dictionary:
			settings.merge(s, true)

func _register_inputs() -> void:
	var key_defs := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"run": [KEY_SHIFT],
		"crouch": [KEY_C, KEY_CTRL],
		"interact": [KEY_E],
		"vault": [KEY_SPACE],
		"inspect": [KEY_I, KEY_TAB],
		"pause": [KEY_ESCAPE, KEY_P],
	}
	for action: String in key_defs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k: Key in key_defs[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var mouse_defs := {"throw": MOUSE_BUTTON_LEFT, "peek": MOUSE_BUTTON_RIGHT}
	for action: String in mouse_defs:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mev := InputEventMouseButton.new()
		mev.button_index = mouse_defs[action]
		InputMap.action_add_event(action, mev)
