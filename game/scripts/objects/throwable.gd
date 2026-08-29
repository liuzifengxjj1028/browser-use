extends RigidBody3D
class_name Throwable
## A small object (stapler) the player can carry (one at a time) and throw
## to create a noise that lures the supervisor (PRD §4, §5).

var state := "idle" # idle | held | flying
var _impact_done := false

func _ready() -> void:
	mass = 0.6
	collision_layer = 8
	collision_mask = 1 | 2 | 8
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

func get_prompt() -> String:
	return Loc.t("PROMPT_PICKUP")

func interact(player: Node) -> void:
	if state == "idle":
		player.pick_throwable(self)

func hold() -> void:
	state = "held"
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func launch(from: Vector3, impulse: Vector3) -> void:
	state = "flying"
	_impact_done = false
	global_position = from
	freeze = false
	collision_layer = 8
	collision_mask = 1 | 8
	apply_central_impulse(impulse)
	apply_torque_impulse(Vector3(randf(), randf(), randf()) * 0.4)
	var t := get_tree().create_timer(2.5)
	t.timeout.connect(func() -> void:
		if state == "flying":
			state = "idle"
			collision_mask = 1 | 2 | 8)

func _on_body_entered(_body: Node) -> void:
	if state != "flying" or _impact_done:
		return
	_impact_done = true
	AudioSynth.play_at("throw_hit", global_position, get_parent(), 2.0)
	Game.emit_noise(global_position, 17.0, 1.0)
