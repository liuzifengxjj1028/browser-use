extends Node3D
class_name HideSpot
## A discrete hiding place (cabinet / under a desk). Not absolutely safe:
## the supervisor checks spots near noises and last-seen positions (PRD §5.3).

var kind := "cabinet" # cabinet | desk
var risk := 0.3       # >= 0.6 gets an explicit environmental hint
var cell := Vector2i.ZERO
var hide_position := Vector3.ZERO
var entry_position := Vector3.ZERO
var occupant: Node = null
var interact_area: Area3D

func setup(p_kind: String, p_risk: float, p_cell: Vector2i, p_hide: Vector3, p_entry: Vector3) -> void:
	kind = p_kind
	risk = p_risk
	cell = p_cell
	hide_position = p_hide
	entry_position = p_entry
	interact_area = Area3D.new()
	interact_area.collision_layer = 16
	interact_area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.0, 1.6)
	cs.shape = box
	interact_area.add_child(cs)
	interact_area.set_meta("owner_node", self)
	add_child(interact_area)
	interact_area.position = to_local(p_entry) + Vector3(0, 1.0, 0)

func get_prompt() -> String:
	if occupant != null:
		return Loc.t("PROMPT_EXIT_HIDE")
	return Loc.t("PROMPT_HIDE_CABINET" if kind == "cabinet" else "PROMPT_HIDE_DESK")

func interact(player: Node) -> void:
	if occupant == player:
		player.exit_hide()
	elif occupant == null:
		player.enter_hide(self)

## Supervisor opens this spot. Returns true if the player was inside.
func open_check(_enemy: Node) -> bool:
	AudioSynth.play_at("door", global_position, self, -4.0)
	return occupant != null
