extends StaticBody3D
class_name Workstation
## A cubicle monitor. Lighting one up is the key puzzle interaction, but a lit
## screen is exactly what the faceless supervisor investigates (PRD §7 level 1).

var id := 0
var is_on := false
var level: Node3D
var screen_mesh: MeshInstance3D

func get_prompt() -> String:
	if is_on:
		return ""
	return Loc.t("PROMPT_WORKSTATION") % id

func interact(_player: Node) -> void:
	if is_on:
		return
	is_on = true
	level.on_workstation_activated(self)

func set_screen(color: Color, energy: float) -> void:
	if screen_mesh == null:
		return
	var mat: StandardMaterial3D = screen_mesh.get_surface_override_material(0)
	if mat == null:
		return
	mat.emission_enabled = energy > 0.0
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.albedo_color = color.darkened(0.6) if energy > 0.0 else Color(0.05, 0.06, 0.08)

func power_off() -> void:
	is_on = false
	set_screen(Color(0, 0, 0), 0.0)
