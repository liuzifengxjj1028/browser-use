extends CharacterBody3D
class_name Player
## Third-person controller. Walk / short sprint / crouch / shoulder peek /
## vault / discrete hide spots / carry+throw one object (PRD §4).

signal prompt_changed(text: String)
signal stamina_changed(v: float)
signal hidden_changed(hidden: bool)
signal held_changed(has_item: bool)
signal inspect_pressed

const WALK_SPEED := 3.0
const RUN_SPEED := 5.4
const CROUCH_SPEED := 1.7
const ACCEL := 14.0
const GRAVITY := 16.0
const MOUSE_SENS := 0.0026
const STAMINA_DRAIN := 1.0 / 4.5
const STAMINA_REGEN := 1.0 / 7.0

var level: Node3D
var yaw := 0.0
var pitch := -0.25
var crouching := false
var stamina := 1.0
var hidden_spot: HideSpot = null
var held_throwable: Throwable = null
var has_clue := false
var control_enabled := true
var vaulting := false
var shoulder := 1.0
var current_interactable: Node = null
var _step_accum := 0.0
var _was_running := false

var yaw_node: Node3D
var pitch_node: Node3D
var spring: SpringArm3D
var camera: Camera3D
var body_mesh: MeshInstance3D
var crouch_shape: CollisionShape3D
var hand: Node3D
var _mesh_yaw := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 8
	crouch_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.7
	crouch_shape.shape = cap
	crouch_shape.position = Vector3(0, 0.85, 0)
	add_child(crouch_shape)

	body_mesh = MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.32
	bm.height = 1.66
	body_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.56, 0.62, 0.72)
	body_mesh.material_override = mat
	body_mesh.position = Vector3(0, 0.85, 0)
	add_child(body_mesh)
	# direction hint: a small darker "visor" box on the facing side
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.26, 0.09, 0.1)
	visor.mesh = vb
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.16, 0.18, 0.24)
	visor.material_override = vmat
	visor.position = Vector3(0, 0.62, -0.30)
	body_mesh.add_child(visor)

	yaw_node = Node3D.new()
	add_child(yaw_node)
	yaw_node.position = Vector3(0, 1.5, 0)
	pitch_node = Node3D.new()
	yaw_node.add_child(pitch_node)
	spring = SpringArm3D.new()
	spring.spring_length = 3.4
	spring.collision_mask = 1
	spring.margin = 0.2
	pitch_node.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 68.0
	spring.add_child(camera)
	camera.position = Vector3.ZERO
	hand = Node3D.new()
	yaw_node.add_child(hand)
	hand.position = Vector3(0.45, -0.35, -0.8)
	camera.current = true

func _unhandled_input(event: InputEvent) -> void:
	if not control_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.25, 0.65)
	elif event.is_action_pressed("crouch"):
		crouching = not crouching
		_apply_crouch()
	elif event.is_action_pressed("peek"):
		shoulder = -shoulder
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("throw"):
		_try_throw()
	elif event.is_action_pressed("vault"):
		_try_vault()
	elif event.is_action_pressed("inspect"):
		if has_clue:
			inspect_pressed.emit()

func _apply_crouch() -> void:
	var cap: CapsuleShape3D = crouch_shape.shape
	cap.height = 1.1 if crouching else 1.7
	crouch_shape.position.y = 0.55 if crouching else 0.85
	var bm: CapsuleMesh = body_mesh.mesh
	bm.height = 1.06 if crouching else 1.66
	body_mesh.position.y = 0.55 if crouching else 0.85
	yaw_node.position.y = 1.05 if crouching else 1.5

func _physics_process(delta: float) -> void:
	yaw_node.rotation.y = yaw
	pitch_node.rotation.x = pitch
	yaw_node.position.x = lerpf(yaw_node.position.x, 0.45 * shoulder, 8.0 * delta)

	if hidden_spot != null or not control_enabled:
		velocity = Vector3.ZERO
		_scan_interactable()
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := (basis_yaw * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var wants_run := Input.is_action_pressed("run") and not crouching and input_dir.length() > 0.1
	var running := wants_run and stamina > 0.05
	if running:
		stamina = maxf(stamina - STAMINA_DRAIN * delta, 0.0)
	else:
		stamina = minf(stamina + STAMINA_REGEN * delta, 1.0)
	stamina_changed.emit(stamina)
	_was_running = running

	var speed := CROUCH_SPEED if crouching else (RUN_SPEED if running else WALK_SPEED)
	var target := wish * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0
	move_and_slide()

	# rotate the visible body toward movement
	var hvel := Vector3(velocity.x, 0, velocity.z)
	if hvel.length() > 0.4:
		_mesh_yaw = lerp_angle(_mesh_yaw, atan2(hvel.x, hvel.z) + PI, 10.0 * delta)
		body_mesh.rotation.y = _mesh_yaw

	# footstep noise (gameplay event + faint sound)
	if hvel.length() > 0.5 and is_on_floor():
		_step_accum += hvel.length() * delta
		var stride := 1.4 if not running else 1.9
		if _step_accum >= stride:
			_step_accum = 0.0
			var radius := 2.5 if crouching else (11.0 if running else 6.0)
			Game.emit_noise(global_position, radius, 0.3 if crouching else 0.5)
			AudioSynth.play_at("step", global_position, level, -18.0 if crouching else -12.0, 1.3)
	_scan_interactable()

func _scan_interactable() -> void:
	var found: Node = null
	if camera != null and hidden_spot == null and control_enabled:
		# cast from the character's head along the camera view direction
		var dir := -camera.global_basis.z
		var from := yaw_node.global_position + dir * 0.1
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 2.8, 1 | 8 | 16, [get_rid()])
		q.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.has("collider"):
			var c: Object = hit["collider"]
			if c is Area3D and c.has_meta("owner_node"):
				c = c.get_meta("owner_node")
			if c != null and c.has_method("get_prompt"):
				found = c
	if hidden_spot != null:
		found = hidden_spot
	if found != current_interactable:
		current_interactable = found
	var text := ""
	if current_interactable != null:
		text = current_interactable.get_prompt()
	prompt_changed.emit(text)

func _try_interact() -> void:
	if hidden_spot != null:
		hidden_spot.interact(self)
		return
	if current_interactable != null and current_interactable.has_method("interact"):
		current_interactable.interact(self)

func enter_hide(spot: HideSpot) -> void:
	if hidden_spot != null:
		return
	hidden_spot = spot
	spot.occupant = self
	velocity = Vector3.ZERO
	crouch_shape.disabled = true
	global_position = spot.hide_position
	body_mesh.visible = false
	AudioSynth.play_at("door", global_position, level, -8.0)
	hidden_changed.emit(true)

func exit_hide() -> void:
	if hidden_spot == null:
		return
	var spot := hidden_spot
	hidden_spot = null
	spot.occupant = null
	global_position = spot.entry_position
	crouch_shape.disabled = false
	body_mesh.visible = true
	AudioSynth.play_at("door", global_position, level, -8.0)
	Game.emit_noise(global_position, 3.0, 0.3)
	hidden_changed.emit(false)

## Forced out (spot opened by the supervisor while catching the player).
func flush_from_hide() -> void:
	if hidden_spot != null:
		exit_hide()

func pick_throwable(t: Throwable) -> void:
	if held_throwable != null:
		# swap: drop current where we stand
		drop_throwable()
	held_throwable = t
	t.hold()
	if t.get_parent() != null:
		t.get_parent().remove_child(t)
	hand.add_child(t)
	t.position = Vector3.ZERO
	t.rotation = Vector3.ZERO
	AudioSynth.play_ui("pickup", -6.0)
	held_changed.emit(true)

func drop_throwable() -> void:
	if held_throwable == null:
		return
	var t := held_throwable
	held_throwable = null
	hand.remove_child(t)
	level.add_child(t)
	t.state = "idle"
	t.freeze = false
	t.collision_layer = 8
	t.collision_mask = 1 | 2 | 8
	t.global_position = global_position + Vector3(0, 0.5, 0)
	held_changed.emit(false)

func _try_throw() -> void:
	if held_throwable == null or hidden_spot != null:
		return
	var t := held_throwable
	held_throwable = null
	hand.remove_child(t)
	level.add_child(t)
	var dir := (-camera.global_basis.z + Vector3.UP * 0.22).normalized()
	var from := yaw_node.global_position + -camera.global_basis.z * 0.6
	t.launch(from, dir * 7.5)
	held_changed.emit(false)

func _try_vault() -> void:
	if vaulting or hidden_spot != null:
		return
	var basis_yaw := Basis(Vector3.UP, yaw)
	var fwd := (basis_yaw * Vector3.FORWARD).normalized()
	var from := global_position + Vector3(0, 0.8, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * 1.4, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.has("collider"):
		return
	var col: Object = hit["collider"]
	if col is Node and (col as Node).is_in_group("vaultable"):
		_do_vault(fwd)

func _do_vault(fwd: Vector3) -> void:
	vaulting = true
	control_enabled = false
	crouch_shape.disabled = true
	velocity = Vector3.ZERO
	var start := global_position
	var mid := start + fwd * 1.2 + Vector3(0, 1.5, 0)
	var target := start + fwd * 2.6
	var tw := create_tween()
	tw.tween_property(self, "global_position", mid, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "global_position", target, 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		vaulting = false
		control_enabled = true
		crouch_shape.disabled = false
		Game.emit_noise(global_position, 5.0, 0.5)
		AudioSynth.play_at("step", global_position, level, -8.0, 0.8))

func is_hidden() -> bool:
	return hidden_spot != null

## How easy the player is to see: 0 hidden, ~0.55 crouched, 1 standing, 1.25 sprinting.
func visibility_factor() -> float:
	if is_hidden():
		return 0.0
	var f := 0.55 if crouching else 1.0
	if _was_running:
		f *= 1.25
	return f

## Point the supervisor's eyes test against.
func sight_target() -> Vector3:
	return global_position + Vector3(0, 0.6 if crouching else 1.25, 0)
