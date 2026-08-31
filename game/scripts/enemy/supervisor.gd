extends CharacterBody3D
class_name Supervisor
## The Faceless Supervisor. State machine per PRD §5.1: patrol, suspect,
## investigate, detect, chase, tense search, calm. Special rule: prioritizes
## lit monitors, stopped devices and empty seats (PRD §7 level 1).

signal caught
signal state_changed(state_name: String)
signal detection_changed(v: float)
signal tension_changed(tense: bool)

enum S { PATROL, SUSPECT, INVESTIGATE, DETECT, CHASE, SEARCH }

const EYE_HEIGHT := 1.85

# base parameters (scaled by dream-collapse stage modifiers)
var walk_speed := 2.5
var chase_speed := 4.9
var sight_range := 13.0
var fov_deg := 104.0
var catch_dist := 1.2
var fill_rate := 1.35

# stage / tension multipliers
var sight_mult := 1.0
var hear_mult := 1.0
var speed_mult := 1.0

var level: Node3D
var player: Player
var state: int = S.PATROL
var tense := false
var detect_meter := 0.0
var last_seen := Vector3.ZERO
var _lose_timer := 0.0
var _state_timer := 0.0
var _scan_dir := 1.0
var _investigate_pos := Vector3.ZERO
var _investigate_priority := 0.0
var _search_timer := 0.0
var _spots_to_check: Array = []
var _checking_spot: HideSpot = null
var _path: Array = []
var _path_i := 0
var _repath_timer := 0.0
var _wp_index := 0
var _waiting := 0.0
var _step_accum := 0.0
var _stuck_timer := 0.0
var _last_pos := Vector3.ZERO
var _noise_strikes := 0.0
var _pending_detect := 0.0

var flashlight: SpotLight3D
var rig: CharacterRig

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 2.1
	cs.shape = cap
	cs.position = Vector3(0, 1.05, 0)
	add_child(cs)

	rig = CharacterRig.new()
	add_child(rig)
	rig.build({
		"height": 2.05,
		"shirt": Color(0.10, 0.10, 0.13),
		"pants": Color(0.09, 0.09, 0.11),
		"shoes": Color(0.05, 0.05, 0.06),
		"skin": Color(0.06, 0.06, 0.07),   # faceless: the head is a matte void
		"sheen": 0.25,
		"tie": Color(0.48, 0.10, 0.12),
		"hat": true,
	})
	# hand-held flashlight body (the SpotLight itself stays at chest height)
	var torch := MeshInstance3D.new()
	var tcm := CylinderMesh.new()
	tcm.top_radius = 0.045
	tcm.bottom_radius = 0.055
	tcm.height = 0.24
	torch.mesh = tcm
	var torch_mat := StandardMaterial3D.new()
	torch_mat.albedo_color = Color(0.25, 0.26, 0.28)
	torch_mat.roughness = 0.4
	torch.material_override = torch_mat
	torch.rotation_degrees.x = 90
	rig.add_child(torch)
	torch.position = Vector3(-0.30, 1.05, -0.25)

	flashlight = SpotLight3D.new()
	flashlight.spot_range = 15.0
	flashlight.spot_angle = 32.0
	flashlight.light_energy = 2.4
	flashlight.shadow_enabled = true
	flashlight.position = Vector3(0, 1.8, 0)
	add_child(flashlight)

	Game.noise_emitted.connect(_on_noise)
	_last_pos = global_position

func apply_stage_mods(mods: Dictionary) -> void:
	sight_mult = float(mods.get("sight_mult", sight_mult))
	hear_mult = float(mods.get("hear_mult", hear_mult))
	speed_mult = float(mods.get("speed_mult", speed_mult))

func _set_state(s: int) -> void:
	if state == s:
		return
	state = s
	_state_timer = 0.0
	state_changed.emit(state_name())
	match s:
		S.DETECT:
			_pending_detect = 0.55
			AudioSynth.play_ui("sting", -2.0)
		S.CHASE:
			_set_tense(true)
		S.SEARCH:
			_search_timer = 0.0
			_spots_to_check = level.spots_near(last_seen, 9.0, tense)
		_:
			pass

func _set_tense(v: bool) -> void:
	if tense == v:
		return
	tense = v
	tension_changed.emit(v)

func state_name() -> String:
	return ["patrol", "suspect", "investigate", "detect", "chase", "search"][state]

func _speed() -> float:
	var base := chase_speed if state in [S.CHASE] else walk_speed
	if state == S.SEARCH or state == S.INVESTIGATE:
		base = walk_speed * 1.25
	if tense:
		base *= 1.18
	return base * speed_mult

# ---------- perception ----------

func _visibility() -> float:
	if player == null or player.is_hidden():
		return 0.0
	var eye := global_position + Vector3(0, EYE_HEIGHT, 0)
	var target := player.sight_target()
	var to := target - eye
	var dist := to.length()
	var range_now := sight_range * sight_mult * (1.15 if tense else 1.0)
	if dist > range_now:
		return 0.0
	var fwd := -global_basis.z
	var ang := rad_to_deg(fwd.angle_to(Vector3(to.x, 0, to.z).normalized()))
	if ang > fov_deg * 0.5 and dist > 1.6:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(eye, target, 1, [get_rid(), player.get_rid()])
	if get_world_3d().direct_space_state.intersect_ray(q).has("collider"):
		return 0.0
	var closeness := 1.0 - dist / range_now
	return clampf((0.35 + 0.65 * closeness) * player.visibility_factor(), 0.0, 1.5)

func _on_noise(pos: Vector3, radius: float, loudness: float) -> void:
	if level == null:
		return
	var dist := global_position.distance_to(pos)
	if dist > radius * hear_mult * (1.25 if tense else 1.0):
		return
	if state in [S.CHASE, S.DETECT]:
		return
	if loudness >= 0.8:
		investigate(pos, 2.0)
		return
	# soft noises (footsteps): repeated strikes raise suspicion
	_noise_strikes += loudness
	if tense or state == S.SEARCH:
		investigate(pos, 1.0)
	elif _noise_strikes >= 1.0:
		_noise_strikes = 0.0
		investigate(pos, 0.6)
	elif state == S.PATROL:
		_face_point(pos)
		_set_state(S.SUSPECT)

## External attractions: noises, lit monitors, the stopped printer.
func investigate(pos: Vector3, priority := 1.0) -> void:
	if state in [S.CHASE, S.DETECT]:
		return
	if state == S.INVESTIGATE and priority < _investigate_priority:
		return
	_investigate_pos = pos
	_investigate_priority = priority
	_path = []
	_checking_spot = null
	_set_state(S.INVESTIGATE)

func _face_point(pos: Vector3) -> void:
	var d := pos - global_position
	if Vector3(d.x, 0, d.z).length() > 0.2:
		rotation.y = atan2(d.x, d.z) + PI

# ---------- main loop ----------

func _physics_process(delta: float) -> void:
	if level == null or player == null:
		return
	_state_timer += delta
	_repath_timer -= delta
	_noise_strikes = maxf(_noise_strikes - 0.15 * delta, 0.0)

	var vis := _visibility()
	match state:
		S.PATROL:
			detect_meter = maxf(detect_meter - 0.5 * delta, 0.0)
			if vis > 0.0:
				detect_meter += vis * fill_rate * delta
				if detect_meter >= 1.0:
					_on_detect()
				elif detect_meter > 0.25:
					_face_point(player.global_position)
					_set_state(S.SUSPECT)
			_tick_patrol(delta)
		S.SUSPECT:
			velocity = Vector3.ZERO
			if vis > 0.0:
				last_seen = player.global_position
				detect_meter += vis * fill_rate * 1.4 * delta
				_face_point(player.global_position)
				if detect_meter >= 1.0:
					_on_detect()
			else:
				detect_meter = maxf(detect_meter - 0.25 * delta, 0.0)
				if _state_timer > 2.4:
					if detect_meter > 0.15:
						investigate(last_seen if last_seen != Vector3.ZERO else global_position - global_basis.z * 3.0, 0.8)
					else:
						detect_meter = 0.0
						_set_state(S.PATROL)
		S.INVESTIGATE:
			if vis > 0.0:
				detect_meter += vis * fill_rate * 1.5 * delta
				last_seen = player.global_position
				if detect_meter >= 1.0:
					_on_detect()
			else:
				detect_meter = maxf(detect_meter - 0.2 * delta, 0.0)
			_tick_investigate(delta)
		S.DETECT:
			velocity = Vector3.ZERO
			_face_point(player.global_position)
			_pending_detect -= delta
			if _pending_detect <= 0.0:
				_set_state(S.CHASE)
		S.CHASE:
			_tick_chase(delta, vis)
		S.SEARCH:
			if vis > 0.0:
				detect_meter += vis * fill_rate * 1.8 * delta
				if detect_meter >= 1.0:
					_on_detect()
			else:
				detect_meter = maxf(detect_meter - 0.3 * delta, 0.0)
			_tick_search(delta)

	detection_changed.emit(clampf(detect_meter, 0.0, 1.0))
	_update_flashlight()
	_move_along_path(delta)
	_footsteps(delta)
	_stuck_check(delta)

func _on_detect() -> void:
	detect_meter = 1.0
	last_seen = player.global_position
	_set_state(S.DETECT)

func _tick_patrol(delta: float) -> void:
	if _waiting > 0.0:
		_waiting -= delta
		velocity = Vector3.ZERO
		rotation.y += _scan_dir * 0.7 * delta
		if _waiting <= 0.0:
			_advance_waypoint()
		return
	if _path.is_empty():
		var wp: Vector3 = level.waypoint(_wp_index)
		if global_position.distance_to(wp) < 0.8:
			_waiting = 2.2
			_scan_dir = -_scan_dir
			# special rule: from a waypoint, drift to any lit monitor nearby
			var lit: Variant = level.nearest_lit_monitor(global_position, 11.0)
			if lit != null:
				_waiting = 0.0
				investigate(lit.global_position, 1.2)
		else:
			_path = level.find_path(global_position, wp)
			_path_i = 0

func _advance_waypoint() -> void:
	_wp_index = (_wp_index + 1) % level.waypoint_count()
	_path = []

func _tick_investigate(delta: float) -> void:
	if _checking_spot != null:
		if not _path.is_empty():
			_state_timer = 0.0
		else:
			velocity = Vector3.ZERO
			if _state_timer > 0.8:
				var found := _checking_spot.open_check(self)
				if found:
					_catch_player(true)
					return
				_checking_spot = null
				_state_timer = 0.0
		return
	if not _path.is_empty():
		_state_timer = 0.0
		return
	if _path.is_empty():
		if global_position.distance_to(Vector3(_investigate_pos.x, global_position.y, _investigate_pos.z)) > 1.2:
			_path = level.find_path(global_position, _investigate_pos)
			_path_i = 0
			if _path.is_empty():
				_finish_investigation()
		else:
			# arrived: look around, then maybe check one nearby hide spot
			velocity = Vector3.ZERO
			rotation.y += _scan_dir * 0.9 * delta
			if _state_timer > 2.6:
				var spots: Array = level.spots_near(_investigate_pos, 4.5, tense or _investigate_priority >= 1.0)
				if not spots.is_empty():
					_go_check_spot(spots[0])
				else:
					_finish_investigation()

func _go_check_spot(spot: HideSpot) -> void:
	_checking_spot = spot
	_path = level.find_path(global_position, spot.entry_position)
	_path_i = 0
	_state_timer = 0.0

func _finish_investigation() -> void:
	level.on_investigated(_investigate_pos)
	_investigate_priority = 0.0
	if tense:
		_set_state(S.SEARCH)
	else:
		_path = []
		_set_state(S.PATROL)

func _tick_chase(delta: float, vis: float) -> void:
	if vis > 0.0 or global_position.distance_to(player.global_position) < 2.5 and not player.is_hidden():
		last_seen = player.global_position
		_lose_timer = 0.0
	else:
		_lose_timer += delta
		if _lose_timer > 2.6:
			detect_meter = 0.4
			_set_state(S.SEARCH)
			return
	var dist := global_position.distance_to(player.global_position)
	if dist < catch_dist and not player.is_hidden():
		_catch_player(false)
		return
	# direct pursuit if a straight line is clear, else grid path to last seen
	var eye := global_position + Vector3(0, 0.5, 0)
	var q := PhysicsRayQueryParameters3D.create(eye, last_seen + Vector3(0, 0.5, 0), 1, [get_rid(), player.get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(q).has("collider"):
		_path = [Vector3(last_seen.x, 0, last_seen.z)]
		_path_i = 0
	elif _repath_timer <= 0.0:
		_repath_timer = 0.45
		_path = level.find_path(global_position, last_seen)
		_path_i = 0

func _tick_search(delta: float) -> void:
	_search_timer += delta
	if _search_timer > 24.0:
		_set_tense(false)
		detect_meter = 0.0
		_spots_to_check = []
		_path = []
		_set_state(S.PATROL)
		level.on_calm()
		return
	if _checking_spot != null:
		if not _path.is_empty():
			_state_timer = 0.0
		elif true:
			velocity = Vector3.ZERO
			if _state_timer > 0.8:
				if _checking_spot.open_check(self):
					_catch_player(true)
					return
				_checking_spot = null
				_state_timer = 0.0
		return
	if _path.is_empty():
		if not _spots_to_check.is_empty():
			var spot: HideSpot = _spots_to_check.pop_front()
			_go_check_spot(spot)
		else:
			var p: Vector3 = level.random_walkable_near(last_seen, 6)
			_path = level.find_path(global_position, p)
			_path_i = 0

func _catch_player(from_spot: bool) -> void:
	if from_spot:
		player.flush_from_hide()
	velocity = Vector3.ZERO
	set_physics_process(false)
	caught.emit()

# ---------- movement ----------

func _move_along_path(delta: float) -> void:
	rig.move_speed = Vector3(velocity.x, 0, velocity.z).length()
	if state == S.SUSPECT or state == S.DETECT:
		return
	if _path.is_empty() or _path_i >= _path.size():
		velocity.x = move_toward(velocity.x, 0, 20 * delta)
		velocity.z = move_toward(velocity.z, 0, 20 * delta)
		if _path_i >= _path.size():
			_path = []
		move_and_slide()
		return
	var target: Vector3 = _path[_path_i]
	var to := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if to.length() < 0.35:
		_path_i += 1
	else:
		var dir := to.normalized()
		var sp := _speed()
		velocity.x = dir.x * sp
		velocity.z = dir.z * sp
		velocity.y = 0
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z) + PI, 9.0 * delta)
	move_and_slide()

func _footsteps(delta: float) -> void:
	var hvel := Vector3(velocity.x, 0, velocity.z)
	if hvel.length() > 0.5:
		_step_accum += hvel.length() * delta
		var stride := 1.7
		if _step_accum >= stride:
			_step_accum = 0.0
			var loud := state == S.CHASE
			AudioSynth.play_at("step_enemy", global_position, level, 2.0 if loud else -3.0, 1.15 if loud else 1.0)

func _stuck_check(delta: float) -> void:
	if _path.is_empty():
		_stuck_timer = 0.0
		_last_pos = global_position
		return
	_stuck_timer += delta
	if _stuck_timer >= 1.2:
		if global_position.distance_to(_last_pos) < 0.15:
			_path = []
			_repath_timer = 0.0
		_stuck_timer = 0.0
		_last_pos = global_position

func _update_flashlight() -> void:
	var c := Color(0.85, 0.9, 1.0)
	match state:
		S.SUSPECT, S.INVESTIGATE:
			c = Color(1.0, 0.75, 0.35)
		S.DETECT, S.CHASE:
			c = Color(1.0, 0.25, 0.2)
		S.SEARCH:
			c = Color(0.9, 0.5, 0.9)
	flashlight.light_color = flashlight.light_color.lerp(c, 0.15)
	flashlight.rotation_degrees.x = -6.0
	if tense:
		flashlight.light_energy = 2.4 + sin(Time.get_ticks_msec() * 0.03) * 0.35 + randf_range(-0.15, 0.15)
	else:
		flashlight.light_energy = lerpf(flashlight.light_energy, 2.4, 0.1)
