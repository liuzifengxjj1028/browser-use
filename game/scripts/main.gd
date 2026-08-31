extends Node
## Application shell: title / gameplay / pause / inspect / fail / ending.
## All UI is built in code; strings come from Loc (zh / en).

enum State { TITLE, PLAYING, PAUSED, INSPECT, FAIL, WIN }

var state: int = State.TITLE
var theme: Theme
var level: OfficeLevel
var hud: Hud
var title_ui: CanvasLayer
var pause_ui: CanvasLayer
var inspect_ui: CanvasLayer
var end_ui: CanvasLayer
var intro_ui: CanvasLayer
var chapter_panel: Control
var _i18n: Array = []           # Callables run on language change
var _won_flag := false
var _fail_reason := ""
var _cup_pivot: Node3D
var _cup_flipped := false
var _clue_revealed := false
var _intro_skip := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.set_default_clear_color(Color(0.03, 0.04, 0.06))
	theme = _make_theme()
	Loc.language_changed.connect(_refresh_i18n)
	_build_title()
	_build_pause()
	_build_end()
	if Game.smoke_test:
		_run_smoke()

func _make_theme() -> Theme:
	var th := Theme.new()
	if ResourceLoader.exists("res://assets/fonts/ui_font.ttf"):
		th.default_font = load("res://assets/fonts/ui_font.ttf")
	th.default_font_size = 16
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.12, 0.16, 0.9)
	normal.border_color = Color(0.35, 0.4, 0.5)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(10)
	normal.content_margin_left = 22
	normal.content_margin_right = 22
	var hover := normal.duplicate()
	hover.bg_color = Color(0.16, 0.19, 0.25, 0.95)
	hover.border_color = Color(0.65, 0.72, 0.85)
	var pressed := hover.duplicate()
	pressed.bg_color = Color(0.2, 0.24, 0.3)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.07, 0.08, 0.1, 0.7)
	disabled.border_color = Color(0.2, 0.22, 0.26)
	for sname in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb: StyleBox = {"normal": normal, "hover": hover, "pressed": pressed,
			"disabled": disabled, "focus": hover}[sname]
		th.set_stylebox(sname, "Button", sb)
	th.set_color("font_color", "Button", Color(0.88, 0.9, 0.94))
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_color("font_disabled_color", "Button", Color(0.45, 0.48, 0.54))
	return th

func _tr_label(l: Label, key: String) -> void:
	l.text = Loc.t(key)
	_i18n.append(func() -> void: l.text = Loc.t(key))

func _tr_button(b: Button, key: String) -> void:
	b.text = Loc.t(key)
	_i18n.append(func() -> void: b.text = Loc.t(key))

func _refresh_i18n() -> void:
	for c: Callable in _i18n:
		c.call()

func _layer(p_layer: int) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = p_layer
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(cl)
	return cl

func _fullrect(parent: Node, bg: Color) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	parent.add_child(root)
	var cr := ColorRect.new()
	cr.color = bg
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cr)
	return root

# ---------------- title ----------------

func _build_title() -> void:
	title_ui = _layer(10)
	var root := _fullrect(title_ui, Color(0.035, 0.045, 0.065))
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	root.add_child(center)

	var eyebrow := Label.new()
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", Color(0.5, 0.58, 0.7))
	_tr_label(eyebrow, "TITLE_EYEBROW")
	center.add_child(eyebrow)

	var big := Label.new()
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_size_override("font_size", 58)
	big.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	_tr_label(big, "TITLE_MAIN")
	center.add_child(big)

	var sub := Label.new()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
	_tr_label(sub, "TITLE_SUB")
	center.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	center.add_child(spacer)

	var start := Button.new()
	_tr_button(start, "BTN_START")
	start.custom_minimum_size = Vector2(280, 0)
	start.pressed.connect(func() -> void: _start_gameplay(false))
	center.add_child(start)

	var chapters := Button.new()
	_tr_button(chapters, "BTN_CHAPTERS")
	chapters.custom_minimum_size = Vector2(280, 0)
	chapters.pressed.connect(func() -> void: chapter_panel.visible = not chapter_panel.visible)
	center.add_child(chapters)

	var lang := Button.new()
	lang.custom_minimum_size = Vector2(280, 0)
	_tr_button(lang, "BTN_LANG")
	lang.pressed.connect(func() -> void: Game.set_lang("en" if Loc.lang == "zh" else "zh"))
	center.add_child(lang)

	var volrow := HBoxContainer.new()
	volrow.alignment = BoxContainer.ALIGNMENT_CENTER
	volrow.add_theme_constant_override("separation", 12)
	center.add_child(volrow)
	var voll := Label.new()
	voll.add_theme_font_size_override("font_size", 13)
	_tr_label(voll, "LBL_VOLUME")
	volrow.add_child(voll)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(Game.settings.get("volume", 0.8))
	slider.custom_minimum_size = Vector2(170, 20)
	slider.value_changed.connect(func(v: float) -> void: Game.set_volume(v))
	volrow.add_child(slider)

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 14)
	center.add_child(spacer2)
	var controls := Label.new()
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_font_size_override("font_size", 12)
	controls.add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.custom_minimum_size = Vector2(660, 0)
	_tr_label(controls, "TITLE_CONTROLS")
	center.add_child(controls)

	var note := Label.new()
	note.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	note.position = Vector2(0, -34)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color(0.4, 0.44, 0.52))
	_tr_label(note, "TITLE_SAVE_NOTE")
	root.add_child(note)

	_build_chapter_panel(root)

func _build_chapter_panel(root: Control) -> void:
	chapter_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.075, 0.1, 0.97)
	sb.border_color = Color(0.3, 0.35, 0.45)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(20)
	chapter_panel.add_theme_stylebox_override("panel", sb)
	chapter_panel.set_anchors_preset(Control.PRESET_CENTER)
	chapter_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chapter_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	chapter_panel.visible = false
	root.add_child(chapter_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	chapter_panel.add_child(v)
	var head := Label.new()
	head.add_theme_font_size_override("font_size", 20)
	_tr_label(head, "BTN_CHAPTERS")
	v.add_child(head)
	for i in 7:
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 0)
		var key := "CH%d" % (i + 1)
		var done := "office" in Game.completed_levels and i == 0
		var texter := func() -> void:
			var t := Loc.t(key)
			if i == 0 and "office" in Game.completed_levels:
				t += "  ✓"
			elif i > 0:
				t += "  " + Loc.t("LOCKED")
			b.text = t
		texter.call()
		_i18n.append(texter)
		b.disabled = i > 0
		if i == 0:
			b.pressed.connect(func() -> void:
				chapter_panel.visible = false
				_start_gameplay(false))
		v.add_child(b)
	var back := Button.new()
	_tr_button(back, "BTN_BACK")
	back.pressed.connect(func() -> void: chapter_panel.visible = false)
	v.add_child(back)

# ---------------- gameplay ----------------

func _start_gameplay(retry: bool) -> void:
	_teardown_level()
	title_ui.visible = false
	_won_flag = false
	state = State.PLAYING
	level = OfficeLevel.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(level)
	hud = Hud.new(theme)
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(hud)
	# wiring
	level.player.prompt_changed.connect(hud.set_prompt)
	level.player.stamina_changed.connect(hud.set_stamina)
	level.player.held_changed.connect(hud.set_held)
	level.player.inspect_pressed.connect(_open_inspect)
	level.enemy.detection_changed.connect(hud.set_detection)
	level.enemy.tension_changed.connect(hud.set_tense)
	level.objective_changed.connect(hud.set_objective)
	level.subtitle_requested.connect(hud.show_subtitle)
	level.cup_inspect_requested.connect(func() -> void:
		hud.set_clue(true)
		_open_inspect())
	level.won.connect(_on_won)
	level.failed.connect(_on_failed)
	hud.set_objective(level.current_objective)
	hud.set_clue(level.cup_taken)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().paused = false
	var show_intro := not retry and "office" not in Game.seen_intros and not Game.smoke_test
	if show_intro:
		_play_intro()
	else:
		hud.show_subtitle("OBJ_FIND_ITEM_SUB", 4.0)

func _teardown_level() -> void:
	for n in [level, hud]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	level = null
	hud = null
	for cl in [inspect_ui, intro_ui]:
		if cl != null and is_instance_valid(cl):
			cl.queue_free()
	inspect_ui = null
	intro_ui = null

func _play_intro() -> void:
	intro_ui = _layer(20)
	var root := _fullrect(intro_ui, Color(0, 0, 0, 1.0))
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BOTH
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9))
	root.add_child(l)
	var hint := Label.new()
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position = Vector2(0, -40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.4, 0.44, 0.5))
	_tr_label(hint, "INTRO_SKIP")
	root.add_child(hint)
	_intro_skip = false
	root.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_intro_skip = true)
	_intro_seq(l, root)

func _intro_seq(l: Label, root: Control) -> void:
	var tw := create_tween()
	for i in 3:
		var key := "INTRO_%d" % (i + 1)
		tw.tween_callback(func() -> void: l.text = Loc.t(key))
		tw.tween_property(l, "modulate:a", 1.0, 0.6).from(0.0)
		tw.tween_interval(2.4)
		tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_property(root, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void:
		Game.mark_intro_seen("office")
		if intro_ui != null:
			intro_ui.queue_free()
			intro_ui = null
		if hud != null:
			hud.show_subtitle("OBJ_FIND_ITEM_SUB", 4.0))
	tw.set_speed_scale(1.0)
	set_process(true)
	_intro_tween = tw

var _intro_tween: Tween

func _process(_delta: float) -> void:
	if _intro_tween != null and _intro_skip:
		_intro_skip = false
		_intro_tween.kill()
		_intro_tween = null
		Game.mark_intro_seen("office")
		if intro_ui != null:
			intro_ui.queue_free()
			intro_ui = null
		if hud != null:
			hud.show_subtitle("OBJ_FIND_ITEM_SUB", 4.0)
	# on the web, Esc silently releases pointer lock: treat that as pause
	if state == State.PLAYING and not Game.smoke_test \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and intro_ui == null:
		_open_pause()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		match state:
			State.PLAYING:
				_open_pause()
			State.PAUSED:
				_close_pause()
			State.INSPECT:
				_close_inspect()

# ---------------- pause ----------------

func _build_pause() -> void:
	pause_ui = _layer(30)
	pause_ui.visible = false
	var root := _fullrect(pause_ui, Color(0.02, 0.03, 0.05, 0.72))
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	root.add_child(box)
	var head := Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 26)
	_tr_label(head, "PAUSE_TITLE")
	box.add_child(head)
	var resume := Button.new()
	resume.custom_minimum_size = Vector2(260, 0)
	_tr_button(resume, "BTN_RESUME")
	resume.pressed.connect(_close_pause)
	box.add_child(resume)
	var restart := Button.new()
	restart.custom_minimum_size = Vector2(260, 0)
	_tr_button(restart, "BTN_RESTART")
	restart.pressed.connect(func() -> void:
		pause_ui.visible = false
		_start_gameplay(true))
	box.add_child(restart)
	var lang := Button.new()
	lang.custom_minimum_size = Vector2(260, 0)
	_tr_button(lang, "BTN_LANG")
	lang.pressed.connect(func() -> void: Game.set_lang("en" if Loc.lang == "zh" else "zh"))
	box.add_child(lang)
	var volrow := HBoxContainer.new()
	volrow.alignment = BoxContainer.ALIGNMENT_CENTER
	volrow.add_theme_constant_override("separation", 12)
	box.add_child(volrow)
	var voll := Label.new()
	voll.add_theme_font_size_override("font_size", 13)
	_tr_label(voll, "LBL_VOLUME")
	volrow.add_child(voll)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(Game.settings.get("volume", 0.8))
	slider.custom_minimum_size = Vector2(170, 20)
	slider.value_changed.connect(func(v: float) -> void: Game.set_volume(v))
	volrow.add_child(slider)
	var quit := Button.new()
	quit.custom_minimum_size = Vector2(260, 0)
	_tr_button(quit, "BTN_TITLE")
	quit.pressed.connect(func() -> void:
		pause_ui.visible = false
		_to_title())
	box.add_child(quit)

func _open_pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	pause_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_pause() -> void:
	if state != State.PAUSED:
		return
	state = State.PLAYING
	pause_ui.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _to_title() -> void:
	_teardown_level()
	get_tree().paused = false
	state = State.TITLE
	title_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ---------------- inspect (PRD §4: examine & rotate the clue item) ----------------

func _open_inspect() -> void:
	if state != State.PLAYING or level == null:
		return
	state = State.INSPECT
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_cup_flipped = false
	inspect_ui = _layer(25)
	var root := _fullrect(inspect_ui, Color(0.02, 0.025, 0.04, 0.9))
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_CENTER)
	h.grow_horizontal = Control.GROW_DIRECTION_BOTH
	h.grow_vertical = Control.GROW_DIRECTION_BOTH
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 40)
	root.add_child(h)

	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.custom_minimum_size = Vector2(380, 380)
	h.add_child(vpc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vpc.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.1, 0.85)
	cam.fov = 40
	vp.add_child(cam)
	var keylight := DirectionalLight3D.new()
	keylight.rotation_degrees = Vector3(-35, 40, 0)
	keylight.light_energy = 1.6
	vp.add_child(keylight)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, -140, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.6, 0.7, 1.0)
	vp.add_child(rim)
	_cup_pivot = Node3D.new()
	vp.add_child(_cup_pivot)
	_build_cup_model(_cup_pivot)
	vpc.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_cup_pivot.rotation.y += ev.relative.x * 0.012
			_cup_pivot.rotation.x = clampf(_cup_pivot.rotation.x + ev.relative.y * 0.012, -2.6, 2.6))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(360, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(col)
	var name_l := Label.new()
	name_l.add_theme_font_size_override("font_size", 24)
	name_l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	_tr_label(name_l, "CUP_NAME")
	col.add_child(name_l)
	var desc := Label.new()
	desc.add_theme_font_size_override("font_size", 15)
	desc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(360, 0)
	_tr_label(desc, "CUP_DESC")
	col.add_child(desc)
	var clue := Label.new()
	clue.add_theme_font_size_override("font_size", 15)
	clue.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	clue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clue.custom_minimum_size = Vector2(360, 0)
	clue.visible = _clue_revealed
	if _clue_revealed:
		clue.text = Loc.t("CUP_CLUE")
	col.add_child(clue)
	var flip := Button.new()
	_tr_button(flip, "BTN_FLIP_CUP")
	flip.pressed.connect(func() -> void:
		_cup_flipped = not _cup_flipped
		var tw := create_tween()
		tw.tween_property(_cup_pivot, "rotation:x", PI * 0.85 if _cup_flipped else 0.0, 0.5)\
			.set_trans(Tween.TRANS_SINE)
		if not _clue_revealed:
			_clue_revealed = true
			clue.text = Loc.t("CUP_CLUE")
			clue.visible = true
			AudioSynth.play_ui("pickup", -4.0)
			level.confirm_clue())
	col.add_child(flip)
	var close := Button.new()
	_tr_button(close, "BTN_CLOSE")
	close.pressed.connect(_close_inspect)
	col.add_child(close)

func _build_cup_model(parent: Node3D) -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.11
	cyl.bottom_radius = 0.085
	cyl.height = 0.15
	body.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.88, 0.83, 0.74)
	mat.roughness = 0.55
	body.material_override = mat
	parent.add_child(body)
	var handle := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.035
	tor.outer_radius = 0.06
	handle.mesh = tor
	handle.material_override = mat
	handle.position = Vector3(0.13, 0, 0)
	handle.rotation_degrees = Vector3(0, 0, 90)
	parent.add_child(handle)
	# the chip on the rim
	var chip := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(0.035, 0.02, 0.035)
	chip.mesh = cb
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.4, 0.36, 0.3)
	chip.material_override = cmat
	chip.position = Vector3(-0.07, 0.075, 0.05)
	parent.add_child(chip)
	# underside: pressed leaf + date
	var leaf := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.06, 0.004, 0.09)
	leaf.mesh = lb
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.45, 0.55, 0.3)
	leaf.material_override = lmat
	leaf.position = Vector3(0.02, -0.078, 0.0)
	leaf.rotation_degrees = Vector3(0, 25, 0)
	parent.add_child(leaf)
	var date := Label3D.new()
	date.text = "10 · 17"
	date.font_size = 64
	date.pixel_size = 0.0008
	date.modulate = Color(0.35, 0.3, 0.25)
	date.position = Vector3(-0.02, -0.077, 0.0)
	date.rotation_degrees = Vector3(90, 0, 0)
	parent.add_child(date)

func _close_inspect() -> void:
	if state != State.INSPECT:
		return
	if inspect_ui != null:
		inspect_ui.queue_free()
		inspect_ui = null
	state = State.PLAYING
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------------- endings ----------------

func _build_end() -> void:
	end_ui = _layer(40)
	end_ui.visible = false

func _show_end(fail: bool, reason: String) -> void:
	for c in end_ui.get_children():
		c.queue_free()
	end_ui.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var root := _fullrect(end_ui, Color(0, 0, 0, 0.0))
	var fade := root.get_child(0) as ColorRect
	fade.color = Color(0.01, 0.01, 0.02, 0.0)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 0.94, 1.1)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.modulate.a = 0.0
	root.add_child(box)
	tw.parallel().tween_property(box, "modulate:a", 1.0, 1.4).set_delay(0.6)
	var head := Label.new()
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 32)
	head.add_theme_color_override("font_color",
		Color(0.85, 0.4, 0.35) if fail else Color(0.7, 0.85, 1.0))
	box.add_child(head)
	var body := Label.new()
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(0.7, 0.74, 0.82))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(560, 0)
	box.add_child(body)
	if fail:
		head.text = Loc.t("FAIL_CAUGHT_TITLE" if reason == "caught" else "FAIL_COLLAPSE_TITLE")
		body.text = Loc.t("FAIL_CAUGHT_BODY" if reason == "caught" else "FAIL_COLLAPSE_BODY")
		var retry := Button.new()
		retry.custom_minimum_size = Vector2(260, 0)
		_tr_button(retry, "BTN_RETRY")
		retry.pressed.connect(func() -> void:
			end_ui.visible = false
			_start_gameplay(true))
		box.add_child(retry)
	else:
		head.text = Loc.t("WIN_TITLE")
		body.text = Loc.t("WIN_BODY")
	var to_title := Button.new()
	to_title.custom_minimum_size = Vector2(260, 0)
	_tr_button(to_title, "BTN_TITLE")
	to_title.pressed.connect(func() -> void:
		end_ui.visible = false
		_to_title())
	box.add_child(to_title)

func _on_failed(reason: String) -> void:
	if state in [State.FAIL, State.WIN]:
		return
	_fail_reason = reason
	state = State.FAIL
	AudioSynth.play_ui("sting", 0.0, 0.7)
	get_tree().paused = true
	_show_end(true, reason)

func _on_won() -> void:
	if state in [State.FAIL, State.WIN]:
		return
	_won_flag = true
	state = State.WIN
	Game.mark_completed("office")
	get_tree().paused = true
	_show_end(false, "")

# ---------------- headless smoke test ----------------

func _run_smoke() -> void:
	var failures: Array = []
	var check := func(cond: bool, label: String) -> void:
		print("[SMOKE] %s: %s" % ["PASS" if cond else "FAIL", label])
		if not cond:
			failures.append(label)
	await get_tree().process_frame
	# locale parity
	var zh_keys: Array = []
	var en_keys: Array = []
	Loc.set_lang("zh"); zh_keys = Loc.keys(); zh_keys.sort()
	Loc.set_lang("en"); en_keys = Loc.keys(); en_keys.sort()
	Loc.set_lang("zh")
	check.call(zh_keys == en_keys and zh_keys.size() > 10, "locale zh/en key parity (%d keys)" % zh_keys.size())

	_start_gameplay(false)
	await get_tree().create_timer(1.0).timeout
	check.call(level != null and level.player != null and level.enemy != null, "level + actors spawned")
	check.call(level.waypoint_count() == 8, "8 patrol waypoints")
	check.call(level.workstations.size() == 8, "8 workstations")
	var path := level.find_path(level.enemy.global_position, level.player.global_position)
	check.call(path.size() > 3, "A* path enemy->player exists (%d nodes)" % path.size())

	# movement
	var p0: Vector3 = level.player.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("move_forward")
	check.call(level.player.global_position.distance_to(p0) > 1.0, "player moves")

	# clue + puzzle chain
	level.player.has_clue = true
	level.confirm_clue()
	var ws := level.workstation_by_id(1017)
	check.call(ws != null, "workstation 1017 exists")
	ws.is_on = true
	level.on_workstation_activated(ws)
	check.call(level.elevator_unlocked, "correct workstation unlocks elevator")
	# wrong workstation attracts
	var wrong: Workstation = null
	for w: Workstation in level.workstations:
		if w.id != 1017:
			wrong = w
			break
	level.on_workstation_activated(wrong)
	await get_tree().create_timer(0.3).timeout

	# win by entering the elevator
	var e_cell := Vector2i(-1, -1)
	for y in level.H:
		for x in level.W:
			if level.grid[y][x] == "E":
				e_cell = Vector2i(x, y)
	level.debug_teleport_player(e_cell)
	await get_tree().create_timer(1.2).timeout
	check.call(_won_flag, "entering open elevator wins the level")

	# retry then get caught
	end_ui.visible = false
	_start_gameplay(true)
	await get_tree().create_timer(0.8).timeout
	var pc := level.world_to_cell(level.player.global_position)
	level.enemy._path = []
	level.enemy._waiting = 10.0
	level.enemy.global_position = level.cell_to_world(pc + Vector2i(0, -1))
	level.enemy._face_point(level.player.global_position)
	await get_tree().create_timer(5.0).timeout
	check.call(state == State.FAIL and _fail_reason == "caught", "detection leads to a catch (state=%s reason=%s enemy=%s)" % [state, _fail_reason, level.enemy.state_name() if level != null and level.enemy != null else "?"])

	# retry and force the collapse timeline
	end_ui.visible = false
	_start_gameplay(true)
	await get_tree().create_timer(0.8).timeout
	var stage_names: Array = []
	level.stage_changed.connect(func(n: String) -> void: stage_names.append(n))
	level.elapsed = 149.0
	await get_tree().create_timer(1.5).timeout
	check.call("anomaly" in stage_names, "stage 2 (anomaly) applies")
	level.elapsed = 299.0
	await get_tree().create_timer(1.5).timeout
	check.call("unravel" in stage_names, "stage 3 (unravel) applies")
	check.call(level._open_walls.is_empty(), "stage 3 opens the 'o' shortcut walls")
	level.elapsed = 434.0
	await get_tree().create_timer(1.5).timeout
	check.call(state == State.FAIL and _fail_reason == "collapse", "stage 4 collapse fails the run")

	# raycast interaction: stand in front of the cup and look at it
	end_ui.visible = false
	_start_gameplay(true)
	await get_tree().create_timer(0.8).timeout
	level.debug_teleport_player(Vector2i(37, 13))
	level.player.yaw = -PI / 2.0
	level.player.pitch = -0.15
	await get_tree().create_timer(0.5).timeout
	check.call(level.player.current_interactable is KeyItem, "camera raycast finds the coffee cup (found=%s)" % [level.player.current_interactable])
	if level.player.current_interactable is KeyItem:
		level.player._try_interact()
		await get_tree().process_frame
		check.call(level.cup_taken and state == State.INSPECT, "E takes the cup and opens the inspect view")
		_close_inspect()

	# noise luring: restart, throw-noise pulls the enemy to investigate
	end_ui.visible = false
	_start_gameplay(true)
	await get_tree().create_timer(0.8).timeout
	var lure := level.enemy.global_position + Vector3(4, 0, 0)
	Game.emit_noise(lure, 17.0, 1.0)
	await get_tree().create_timer(1.0).timeout
	check.call(level.enemy.state_name() in ["investigate", "suspect"], "loud noise triggers investigation (state=%s)" % level.enemy.state_name())

	print("[SMOKE] ---- %d failure(s) ----" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
