extends CanvasLayer
class_name Hud
## Minimal diegetic-leaning HUD (PRD §10): no minimap, no timer, no enemy
## position. Only prompts, objective, held items, stamina and alert feedback.

var prompt_label: Label
var objective_label: Label
var clue_label: Label
var held_label: Label
var subtitle_label: Label
var stamina_bar: ProgressBar
var detect_bar: ProgressBar
var vignette: ColorRect
var _vignette_mat: ShaderMaterial
var _tense := false
var _heartbeat_timer := 0.0
var _subtitle_tween: Tween
var ui_theme: Theme

func _init(theme: Theme) -> void:
	ui_theme = theme

func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ui_theme
	add_child(root)

	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv) * 1.7;
	COLOR = vec4(0.45, 0.03, 0.03, intensity * smoothstep(0.35, 1.05, d));
}
"""
	_vignette_mat = ShaderMaterial.new()
	_vignette_mat.shader = sh
	_vignette_mat.set_shader_parameter("intensity", 0.0)
	vignette.material = _vignette_mat
	root.add_child(vignette)

	# crosshair dot
	var dot := ColorRect.new()
	dot.color = Color(0.9, 0.92, 0.95, 0.55)
	dot.custom_minimum_size = Vector2(3, 3)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = Vector2(-1.5, -1.5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)

	objective_label = _label(root, 15, Color(0.78, 0.82, 0.9))
	objective_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	objective_label.position = Vector2(24, 20)

	clue_label = _label(root, 14, Color(0.95, 0.8, 0.5))
	clue_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	clue_label.position = Vector2(24, -74)
	clue_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	held_label = _label(root, 14, Color(0.75, 0.78, 0.85))
	held_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	held_label.position = Vector2(24, -44)
	held_label.grow_vertical = Control.GROW_DIRECTION_BEGIN

	subtitle_label = _label(root, 18, Color(0.92, 0.93, 0.96))
	subtitle_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	subtitle_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	subtitle_label.position = Vector2(0, -120)
	subtitle_label.modulate.a = 0.0

	prompt_label = _label(root, 15, Color(0.9, 0.92, 0.96))
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_label.position = Vector2(0, -78)

	stamina_bar = _bar(root, Color(0.65, 0.75, 0.85))
	stamina_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	stamina_bar.position = Vector2(-70, -52)
	stamina_bar.size = Vector2(140, 4)
	stamina_bar.value = 100

	detect_bar = _bar(root, Color(0.95, 0.55, 0.3))
	detect_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	detect_bar.position = Vector2(-60, 36)
	detect_bar.size = Vector2(120, 5)
	detect_bar.value = 0

func _label(parent: Control, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _bar(parent: Control, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.max_value = 100
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b

func set_prompt(text: String) -> void:
	prompt_label.text = text

func set_objective(key: String) -> void:
	objective_label.text = Loc.t("OBJ_PREFIX") + Loc.t(key)

func set_clue(visible_clue: bool) -> void:
	clue_label.text = Loc.t("HUD_CLUE") if visible_clue else ""

func set_held(has_item: bool) -> void:
	held_label.text = Loc.t("HUD_HELD") if has_item else ""

func set_stamina(v: float) -> void:
	stamina_bar.value = v * 100.0
	stamina_bar.visible = v < 0.995

func set_detection(v: float) -> void:
	detect_bar.value = v * 100.0
	detect_bar.visible = v > 0.03

func set_tense(v: bool) -> void:
	_tense = v

func show_subtitle(key: String, duration: float) -> void:
	subtitle_label.text = Loc.t(key)
	if _subtitle_tween != null:
		_subtitle_tween.kill()
	subtitle_label.modulate.a = 0.0
	_subtitle_tween = create_tween()
	_subtitle_tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.3)
	_subtitle_tween.tween_interval(duration)
	_subtitle_tween.tween_property(subtitle_label, "modulate:a", 0.0, 0.6)

func _process(delta: float) -> void:
	var target := 0.55 if _tense else 0.10
	var cur: Variant = _vignette_mat.get_shader_parameter("intensity")
	var curf := float(cur) if cur != null else 0.0
	_vignette_mat.set_shader_parameter("intensity", lerpf(curf, target, delta * 3.0))
	if _tense:
		_heartbeat_timer -= delta
		if _heartbeat_timer <= 0.0:
			_heartbeat_timer = 0.75
			AudioSynth.play_ui("heartbeat", -6.0)
