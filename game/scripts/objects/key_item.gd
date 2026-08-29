extends StaticBody3D
class_name KeyItem
## The lover's personal item for this layer: a chipped coffee cup (PRD §7).

var level: Node3D

func get_prompt() -> String:
	return Loc.t("PROMPT_TAKE_CUP")

func interact(_player: Node) -> void:
	level.on_cup_taken(self)
