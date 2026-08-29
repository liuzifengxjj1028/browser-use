extends Node3D
class_name OfficeLevel
## Level 1 "The Office — Estrangement". The whole grey-box scene is built at
## runtime from an ASCII map in data/levels/office.json (data-driven, PRD §12).

signal won
signal failed(reason: String)
signal objective_changed(key: String)
signal stage_changed(stage_name: String)
signal subtitle_requested(key: String, duration: float)
signal cup_inspect_requested

const CELL := 2.0
const WALL_H := 3.0

var config: Dictionary = {}
var grid: Array = []            # Array[Array[String]] per row
var W := 0
var H := 0
var astar := AStarGrid2D.new()
var player: Player
var enemy: Supervisor
var hide_spots: Array = []
var workstations: Array = []
var waypoints: Array = []       # ordered Vector3
var elevator_unlocked := false
var clue_found := false
var cup_taken := false
var elapsed := 0.0
var stage_index := 0
var _warned := {}
var _pending_close: Array = []  # cells waiting to close (occupied)
var _retry_timer := 0.0
var _open_walls: Dictionary = {}   # Vector2i -> Node ('o' walls)
var _lights: Array = []
var _flicker_level := 0
var _flicker_timer := 0.0
var _ambient_target := 1.0
var _env: Environment
var _printer: Node3D = null
var _printer_hum: AudioStreamPlayer3D = null
var _elevator_doors: Array = []
var _elevator_lamp: OmniLight3D = null
var _cup_node: Node3D = null
var _finished := false
var current_objective := "OBJ_FIND_ITEM"

var _mats := {}

func _emit_objective(key: String) -> void:
	current_objective = key
	objective_changed.emit(key)

func _ready() -> void:
	_load_config()
	_make_materials()
	_build_environment()
	_parse_and_build()
	_build_astar()
	_spawn_actors()
	_emit_objective("OBJ_FIND_ITEM")

func _load_config() -> void:
	var f := FileAccess.open("res://data/levels/office.json", FileAccess.READ)
	config = JSON.parse_string(f.get_as_text())
	var rows: Array = config["map"]
	H = rows.size()
	W = str(rows[0]).length()
	for row in rows:
		var chars: Array = []
		for i in W:
			chars.append(str(row)[i])
		grid.append(chars)

func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * CELL, 0.0, (c.y + 0.5) * CELL)

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))

func at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return "#"
	return grid[c.y][c.x]

# ---------- materials / environment ----------

func _mat(name: String, color: Color, rough := 0.9, emis := Color(0, 0, 0), emis_e := 0.0) -> StandardMaterial3D:
	if _mats.has(name):
		return _mats[name]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	_mats[name] = m
	return m

func _make_materials() -> void:
	_mat("floor", Color(0.21, 0.22, 0.26))
	_mat("ceil", Color(0.10, 0.11, 0.13))
	_mat("wall", Color(0.36, 0.38, 0.45))
	_mat("wall_glitch", Color(0.36, 0.22, 0.38))
	_mat("partition", Color(0.34, 0.38, 0.47))
	_mat("desk", Color(0.36, 0.30, 0.24))
	_mat("monitor", Color(0.09, 0.10, 0.12))
	_mat("cabinet", Color(0.30, 0.34, 0.30))
	_mat("cabinet_worn", Color(0.42, 0.36, 0.26))
	_mat("table", Color(0.42, 0.38, 0.33))
	_mat("elev", Color(0.45, 0.48, 0.54), 0.4)
	_mat("printer", Color(0.55, 0.56, 0.58))
	_mat("cup", Color(0.85, 0.80, 0.72))
	_mat("stapler", Color(0.65, 0.25, 0.2))
	_mat("scuff", Color(0.08, 0.07, 0.06))

func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.04, 0.05, 0.07)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.52, 0.57, 0.68)
	_env.ambient_light_energy = 1.55
	_env.fog_light_color = Color(0.35, 0.30, 0.45)
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)

# ---------- geometry ----------

func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D, parent: Node = self, with_body := true, layer := 1) -> Node3D:
	var root: Node3D
	if with_body:
		var body := StaticBody3D.new()
		body.collision_layer = layer
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		root = body
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	root.add_child(mi)
	parent.add_child(root)
	root.position = pos
	return root

func _parse_and_build() -> void:
	# floor + ceiling in 12x12-cell chunks (keeps per-mesh light counts low)
	var chunk := 12
	for cy in range(0, H, chunk):
		for cx in range(0, W, chunk):
			var w := mini(chunk, W - cx) * CELL
			var h := mini(chunk, H - cy) * CELL
			var center := Vector3(cx * CELL + w / 2.0, 0, cy * CELL + h / 2.0)
			_box(Vector3(w, 0.2, h), center + Vector3(0, -0.1, 0), _mat("floor", Color()))
			_box(Vector3(w, 0.2, h), center + Vector3(0, WALL_H + 0.1, 0), _mat("ceil", Color()), self, false)

	var monitor_ids: Array = config.get("monitor_ids", [])
	var mon_i := 0
	var cab_i := 0
	var high_risk: Array = config.get("high_risk_cabinets", [])

	for y in H:
		var x := 0
		while x < W:
			var ch: String = grid[y][x]
			if ch == "#":
				# greedy horizontal merge of plain walls
				var run := 0
				while x + run < W and grid[y][x + run] == "#":
					run += 1
				var size := Vector3(run * CELL, WALL_H, CELL)
				var pos := Vector3(x * CELL + size.x / 2.0, WALL_H / 2.0, (y + 0.5) * CELL)
				_box(size, pos, _mat("wall", Color()))
				x += run
				continue
			var c := Vector2i(x, y)
			var wp := cell_to_world(c)
			match ch:
				"o":
					var wnode := _box(Vector3(CELL, WALL_H, CELL), wp + Vector3(0, WALL_H / 2.0, 0), _mat("wall_glitch", Color()))
					_open_walls[c] = wnode
				"v":
					var p := _box(Vector3(CELL, 1.1, 0.4), wp + Vector3(0, 0.55, 0), _mat("partition", Color()))
					# orient across the gap: if neighbors left/right are walls, keep X; else rotate
					if at(c + Vector2i.LEFT) not in ["#", "v", "o"] and at(c + Vector2i.RIGHT) not in ["#", "v", "o"]:
						p.rotation.y = PI / 2.0
					p.add_to_group("vaultable")
				"d", "U", "M":
					_build_desk(c, ch, monitor_ids, mon_i)
					if ch == "M":
						mon_i += 1
				"C":
					var risky := cab_i in high_risk
					_build_cabinet(c, 0.75 if risky else 0.3)
					cab_i += 1
				"t":
					_box(Vector3(1.8, 0.85, 1.8), wp + Vector3(0, 0.425, 0), _mat("table", Color()))
				"p":
					_build_printer(c)
				"K":
					_build_cup(c)
				"T":
					_build_throwable(c)
				"e":
					_build_elevator_door(c)
				"E":
					pass
				"P", "G", "x", "y", "+", ".":
					pass
				_:
					if ch >= "1" and ch <= "9":
						pass
			x += 1

	# ordered patrol waypoints
	var wp_cells := {}
	for y in H:
		for x in W:
			var ch: String = grid[y][x]
			if ch >= "1" and ch <= "9":
				wp_cells[int(ch)] = Vector2i(x, y)
	var idxs := wp_cells.keys()
	idxs.sort()
	for i: int in idxs:
		waypoints.append(cell_to_world(wp_cells[i]))

	_build_elevator_interior()
	_build_lights()

func _front_dir(c: Vector2i) -> Vector2i:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if at(c + d) in [".", "P", "G", "+", "x", "y", "K", "T"] or (at(c + d) >= "1" and at(c + d) <= "9"):
			return d
	return Vector2i(0, 1)

func _build_desk(c: Vector2i, ch: String, monitor_ids: Array, mon_i: int) -> void:
	var wp := cell_to_world(c)
	var f := _front_dir(c)
	var fv := Vector3(f.x, 0, f.y)
	# desk top slab + two side panels; space under it stays open visually
	_box(Vector3(1.9, 0.1, 1.9), wp + Vector3(0, 0.72, 0), _mat("desk", Color()))
	var side_axis := Vector3(abs(f.y), 0, abs(f.x))  # perpendicular to front
	for s in [-1.0, 1.0]:
		_box(Vector3(0.12 if side_axis.x > 0 else 1.7, 0.7, 0.12 if side_axis.z > 0 else 1.7),
			wp + side_axis * 0.85 * s + Vector3(0, 0.35, 0), _mat("desk", Color()))
	# invisible full-cell blocker so nobody walks through the desk while standing
	var blocker := StaticBody3D.new()
	blocker.collision_layer = 1
	blocker.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.9, 1.4, 1.9)
	cs.shape = bs
	blocker.add_child(cs)
	add_child(blocker)
	blocker.position = wp + Vector3(0, 1.1, 0)

	if ch == "U":
		var spot := HideSpot.new()
		add_child(spot)
		spot.position = wp
		spot.setup("desk", 0.3, c, wp + Vector3(0, 0.0, 0), cell_to_world(c + f))
		hide_spots.append(spot)
	if ch == "M":
		var id := 0
		if mon_i < monitor_ids.size():
			id = int(monitor_ids[mon_i])
		var ws := Workstation.new()
		ws.id = id
		ws.level = self
		ws.collision_layer = 16
		ws.collision_mask = 0
		var wcs := CollisionShape3D.new()
		var wbs := BoxShape3D.new()
		wbs.size = Vector3(0.8, 0.6, 0.3)
		wcs.shape = wbs
		ws.add_child(wcs)
		var frame := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.72, 0.46, 0.1)
		frame.mesh = fm
		frame.material_override = _mat("monitor", Color())
		ws.add_child(frame)
		var screen := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.62, 0.36, 0.02)
		screen.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.05, 0.06, 0.08)
		screen.set_surface_override_material(0, smat)
		screen.position = Vector3(0, 0, 0.06)
		ws.add_child(screen)
		ws.screen_mesh = screen
		var lbl := Label3D.new()
		lbl.text = str(id)
		lbl.font_size = 40
		lbl.modulate = Color(0.75, 0.78, 0.85)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, 0.55, 0)
		ws.add_child(lbl)
		add_child(ws)
		ws.position = wp + Vector3(0, 1.05, 0) - fv * 0.55
		ws.look_at(ws.global_position + fv, Vector3.UP)
		workstations.append(ws)

func _build_cabinet(c: Vector2i, risk: float) -> void:
	var wp := cell_to_world(c)
	var f := _front_dir(c)
	var fv := Vector3(f.x, 0, f.y)
	var mat := _mat("cabinet_worn", Color()) if risk >= 0.6 else _mat("cabinet", Color())
	_box(Vector3(1.3, 2.2, 1.0), wp + Vector3(0, 1.1, 0) - fv * 0.3, mat)
	# door panel; risky cabinets sit ajar with a scuffed floor: the explicit
	# environmental warning required by PRD §5.3
	var door := _box(Vector3(1.1, 2.0, 0.08), wp + Vector3(0, 1.0, 0) + fv * 0.25, mat, self, false)
	if risk >= 0.6:
		door.rotation.y = 0.5
		door.position += fv * 0.2
		_box(Vector3(0.9, 0.02, 0.7), cell_to_world(c + f) + Vector3(0, 0.011, 0), _mat("scuff", Color()), self, false)
	var spot := HideSpot.new()
	add_child(spot)
	spot.position = wp
	spot.setup("cabinet", risk, c, wp, cell_to_world(c + f))
	hide_spots.append(spot)

func _build_printer(c: Vector2i) -> void:
	var wp := cell_to_world(c)
	_printer = _box(Vector3(1.2, 1.1, 1.0), wp + Vector3(0, 0.55, 0), _mat("printer", Color()))
	_printer_hum = AudioStreamPlayer3D.new()
	_printer_hum.stream = AudioSynth.stream("hum")
	_printer_hum.unit_size = 4.0
	_printer_hum.max_distance = 18.0
	_printer.add_child(_printer_hum)
	_printer_hum.play()

func _build_cup(c: Vector2i) -> void:
	var wp := cell_to_world(c)
	_box(Vector3(0.8, 0.9, 0.8), wp + Vector3(0, 0.45, 0), _mat("table", Color()))
	var cup := KeyItem.new()
	cup.level = self
	cup.collision_layer = 16
	cup.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.6, 0.6)
	cs.shape = bs
	cup.add_child(cs)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.11
	cyl.bottom_radius = 0.09
	cyl.height = 0.16
	mi.mesh = cyl
	mi.material_override = _mat("cup", Color())
	cup.add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.82, 0.5)
	glow.omni_range = 2.5
	glow.light_energy = 1.4
	cup.add_child(glow)
	add_child(cup)
	cup.position = wp + Vector3(0, 1.0, 0)
	_cup_node = cup

func _build_throwable(c: Vector2i) -> void:
	var t := Throwable.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.3, 0.14, 0.2)
	cs.shape = bs
	t.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.14, 0.2)
	mi.mesh = bm
	mi.material_override = _mat("stapler", Color())
	t.add_child(mi)
	add_child(t)
	t.position = cell_to_world(c) + Vector3(0, 0.6, 0)

func _build_elevator_door(c: Vector2i) -> void:
	var wp := cell_to_world(c)
	var door := _box(Vector3(0.3, 2.8, CELL), wp + Vector3(CELL * 0.35, 1.4, 0), _mat("elev", Color()))
	_elevator_doors.append(door)

func _build_elevator_interior() -> void:
	var cells: Array = []
	for y in H:
		for x in W:
			if grid[y][x] == "E":
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return
	var center := Vector3.ZERO
	for c: Vector2i in cells:
		center += cell_to_world(c)
	center /= cells.size()
	_elevator_lamp = OmniLight3D.new()
	_elevator_lamp.light_color = Color(0.9, 0.3, 0.25)
	_elevator_lamp.omni_range = 4.0
	_elevator_lamp.light_energy = 1.2
	add_child(_elevator_lamp)
	_elevator_lamp.position = center + Vector3(0, 2.4, 0)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(CELL, 2.8, cells.size() * CELL + CELL)
	cs.shape = bs
	area.add_child(cs)
	add_child(area)
	area.position = center + Vector3(0, 1.4, 0)
	area.body_entered.connect(func(body: Node) -> void:
		if body is Player and elevator_unlocked and not _finished:
			_finished = true
			AudioSynth.play_ui("elevator", 0.0)
			won.emit())

func _build_lights() -> void:
	for y in H:
		for x in W:
			if grid[y][x] in ["#", "o"]:
				continue
			if x % 7 == 3 and y % 5 == 2:
				var l := OmniLight3D.new()
				l.omni_range = 10.0
				l.light_energy = 1.35
				l.light_color = Color(0.82, 0.86, 0.95)
				add_child(l)
				l.position = cell_to_world(Vector2i(x, y)) + Vector3(0, 2.7, 0)
				_lights.append(l)

# ---------- pathfinding grid ----------

const SOLID_CHARS := ["#", "o", "d", "U", "M", "C", "t", "v", "p", "e", "E"]

func _build_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for y in H:
		for x in W:
			if grid[y][x] in SOLID_CHARS:
				astar.set_point_solid(Vector2i(x, y), true)

func is_cell_walkable(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= W or c.y >= H:
		return false
	return not astar.is_point_solid(c)

func _nearest_walkable(c: Vector2i) -> Vector2i:
	if is_cell_walkable(c):
		return c
	for r in range(1, 7):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if is_cell_walkable(n):
					return n
	return c

func find_path(from: Vector3, to: Vector3) -> Array:
	var a := _nearest_walkable(world_to_cell(from))
	var b := _nearest_walkable(world_to_cell(to))
	var ids := astar.get_id_path(a, b)
	var out: Array = []
	for i in ids.size():
		if i == 0 and ids.size() > 1:
			continue  # skip current cell
		out.append(cell_to_world(ids[i]))
	return out

func random_walkable_near(pos: Vector3, radius_cells: int) -> Vector3:
	var c := world_to_cell(pos)
	for _i in 14:
		var n := c + Vector2i(randi_range(-radius_cells, radius_cells), randi_range(-radius_cells, radius_cells))
		if is_cell_walkable(n):
			return cell_to_world(n)
	return pos

func spots_near(pos: Vector3, radius: float, include_low_risk: bool) -> Array:
	var out: Array = []
	for s: HideSpot in hide_spots:
		if s.global_position.distance_to(pos) <= radius and (include_low_risk or s.risk >= 0.5):
			out.append(s)
	out.sort_custom(func(a: HideSpot, b: HideSpot) -> bool:
		if absf(a.risk - b.risk) > 0.01:
			return a.risk > b.risk
		return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	return out.slice(0, 3)

func waypoint(i: int) -> Vector3:
	return waypoints[i % waypoints.size()]

func waypoint_count() -> int:
	return waypoints.size()

# ---------- actors ----------

func _find_char(ch: String) -> Vector2i:
	for y in H:
		for x in W:
			if grid[y][x] == ch:
				return Vector2i(x, y)
	return Vector2i(1, 1)

func _spawn_actors() -> void:
	player = Player.new()
	player.level = self
	add_child(player)
	player.position = cell_to_world(_find_char("P"))

	enemy = Supervisor.new()
	enemy.level = self
	enemy.player = player
	var ec: Dictionary = config.get("enemy", {})
	enemy.walk_speed = float(ec.get("walk_speed", 2.5))
	enemy.chase_speed = float(ec.get("chase_speed", 4.9))
	enemy.sight_range = float(ec.get("sight_range", 13.0))
	enemy.fov_deg = float(ec.get("fov_deg", 104.0))
	add_child(enemy)
	enemy.position = cell_to_world(_find_char("G"))
	enemy.caught.connect(func() -> void:
		if not _finished:
			_finished = true
			failed.emit("caught"))

# ---------- gameplay hooks ----------

func on_cup_taken(cup: KeyItem) -> void:
	cup_taken = true
	player.has_clue = true
	AudioSynth.play_ui("pickup", -2.0)
	cup.queue_free()
	_cup_node = null
	_emit_objective("OBJ_INSPECT")
	cup_inspect_requested.emit()

func confirm_clue() -> void:
	if clue_found:
		return
	clue_found = true
	_emit_objective("OBJ_WS")

func on_workstation_activated(ws: Workstation) -> void:
	var correct := int(config.get("correct_monitor", -1))
	if ws.id == correct:
		if clue_found:
			ws.set_screen(Color(0.55, 0.9, 1.0), 2.2)
			AudioSynth.play_ui("monitor_on", 0.0)
			_unlock_elevator()
		else:
			ws.is_on = false
			ws.set_screen(Color(1.0, 0.6, 0.2), 1.2)
			AudioSynth.play_ui("monitor_bad", -6.0)
			subtitle_requested.emit("WS_LOCKED_HINT", 3.5)
			get_tree().create_timer(2.0).timeout.connect(ws.power_off)
	else:
		ws.set_screen(Color(0.9, 0.3, 0.3), 1.6)
		AudioSynth.play_ui("monitor_bad", -2.0)
		subtitle_requested.emit("WS_WRONG", 3.0)
		Game.emit_noise(ws.global_position, 11.0, 0.85)

func _unlock_elevator() -> void:
	if elevator_unlocked:
		return
	elevator_unlocked = true
	subtitle_requested.emit("ELEVATOR_OPEN", 4.0)
	_emit_objective("OBJ_ESCAPE")
	AudioSynth.play_ui("elevator", 0.0)
	if _elevator_lamp != null:
		_elevator_lamp.light_color = Color(0.4, 1.0, 0.6)
		_elevator_lamp.light_energy = 2.0
	for door: Node3D in _elevator_doors:
		var tw := create_tween()
		tw.tween_property(door, "position:z", door.position.z + CELL * 0.95, 1.2)\
			.set_trans(Tween.TRANS_SINE)
		for child in door.get_children():
			if child is CollisionShape3D:
				child.set_deferred("disabled", true)

func nearest_lit_monitor(pos: Vector3, radius: float) -> Workstation:
	var best: Workstation = null
	var best_d := radius
	for ws: Workstation in workstations:
		if not ws.is_on:
			continue
		if elevator_unlocked and ws.id == int(config.get("correct_monitor", -1)):
			continue
		var d := ws.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = ws
	return best

func on_investigated(pos: Vector3) -> void:
	# the supervisor switches off any lit monitor he reached
	for ws: Workstation in workstations:
		if ws.is_on and ws.global_position.distance_to(pos) < 2.5:
			if elevator_unlocked and ws.id == int(config.get("correct_monitor", -1)):
				continue
			ws.power_off()
			AudioSynth.play_at("monitor_on", ws.global_position, self, -10.0, 0.6)

func on_calm() -> void:
	subtitle_requested.emit("CALM", 2.5)

# ---------- dream collapse timeline (PRD §6) ----------

func _process(delta: float) -> void:
	if _finished:
		return
	elapsed += delta
	var stages: Array = config.get("collapse", {}).get("stages", [])
	var warn_before := float(config.get("collapse", {}).get("warn_before", 15.0))
	# warnings
	for i in stages.size():
		var st: Dictionary = stages[i]
		var wc: String = str(st.get("warn_cue", ""))
		if wc != "" and not _warned.has(i) and elapsed >= float(st["t"]) - warn_before:
			_warned[i] = true
			subtitle_requested.emit(wc, 4.0)
			AudioSynth.play_ui("whistle_low", -8.0, 0.6)
	# stage advance
	if stage_index + 1 < stages.size() and elapsed >= float(stages[stage_index + 1]["t"]):
		stage_index += 1
		_apply_stage(stages[stage_index])
	# pending closures blocked by an occupied cell
	_retry_timer -= delta
	if _retry_timer <= 0.0 and not _pending_close.is_empty():
		_retry_timer = 0.8
		var still: Array = []
		for c: Vector2i in _pending_close:
			if not _try_close_cell(c):
				still.append(c)
		_pending_close = still
	# flicker
	if _flicker_level > 0:
		_flicker_timer -= delta
		if _flicker_timer <= 0.0:
			_flicker_timer = randf_range(0.06, 0.5 / _flicker_level)
			for l: OmniLight3D in _lights:
				if randf() < 0.25 * _flicker_level:
					l.light_energy = randf_range(0.25, 1.15)
	_env.ambient_light_energy = lerpf(_env.ambient_light_energy, _ambient_target, delta * 1.5)
	# safety: player fell out of the world
	if player != null and player.global_position.y < -6.0:
		player.global_position = cell_to_world(_find_char("P")) + Vector3(0, 0.5, 0)

func _apply_stage(st: Dictionary) -> void:
	var st_name := str(st.get("name", ""))
	stage_changed.emit(st_name)
	if st_name == "collapse":
		_finished = true
		failed.emit("collapse")
		return
	var cue := str(st.get("cue", ""))
	if cue != "":
		subtitle_requested.emit(cue, 4.5)
	AudioSynth.play_ui("static", -10.0, 0.7)
	_ambient_target = float(st.get("ambient", 1.0))
	_env.fog_enabled = float(st.get("fog", 0.0)) > 0.0
	_env.fog_density = float(st.get("fog", 0.0))
	_flicker_level = int(st.get("flicker", 0))
	# map mutation
	var close_char := str(st.get("close", ""))
	if close_char != "":
		for y in H:
			for x in W:
				if grid[y][x] == close_char:
					var c := Vector2i(x, y)
					if not _try_close_cell(c):
						_pending_close.append(c)
	var open_char := str(st.get("open", ""))
	if open_char == "o":
		for c: Vector2i in _open_walls:
			var node: Node3D = _open_walls[c]
			astar.set_point_solid(c, false)
			var tw := create_tween()
			tw.tween_property(node, "scale:y", 0.02, 0.8)
			tw.tween_callback(node.queue_free)
			AudioSynth.play_at("static", cell_to_world(c), self, -8.0)
		_open_walls.clear()
	# enemy modifiers
	var mods: Variant = st.get("enemy", null)
	if mods is Dictionary and enemy != null:
		enemy.apply_stage_mods(mods)

func _try_close_cell(c: Vector2i) -> bool:
	var wp := cell_to_world(c)
	for actor: Node3D in [player, enemy]:
		if actor != null and Vector3(actor.global_position.x - wp.x, 0, actor.global_position.z - wp.z).length() < 1.7:
			return false
	astar.set_point_solid(c, true)
	var wall := _box(Vector3(CELL, WALL_H, CELL), wp + Vector3(0, WALL_H / 2.0, 0), _mat("wall_glitch", Color()))
	wall.scale.y = 0.02
	var tw := create_tween()
	tw.tween_property(wall, "scale:y", 1.0, 0.9).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	AudioSynth.play_at("static", wp, self, -6.0)
	# anomaly flavor once: the printer dies and the supervisor goes to look
	if _printer_hum != null and _printer_hum.playing:
		_printer_hum.stop()
		subtitle_requested.emit("ANOM_PRINTER", 3.5)
		if enemy != null and _printer != null:
			get_tree().create_timer(1.8).timeout.connect(func() -> void:
				if enemy != null:
					enemy.investigate(_printer.global_position, 1.1))
		_printer_hum = null
	return true

# smoke-test helpers
func debug_teleport_player(c: Vector2i) -> void:
	player.global_position = cell_to_world(c) + Vector3(0, 0.2, 0)

func workstation_by_id(id: int) -> Workstation:
	for ws: Workstation in workstations:
		if ws.id == id:
			return ws
	return null
