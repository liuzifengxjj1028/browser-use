class_name CharacterRig
extends Node3D
## Low-poly blocky humanoid with procedural walk/idle/crouch animation.
## Shared by the player and the Faceless Supervisor.

var move_speed := 0.0          # horizontal speed, set by the owner each frame
var crouching := false

var _root: Node3D              # bobs with the gait
var _torso: MeshInstance3D
var _head: Node3D
var _thigh_l: Node3D
var _thigh_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _phase := 0.0
var _crouch_amt := 0.0
var _base_y := 0.0
var _scale_h := 1.0

static func _m(color: Color, rough := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat

static func _bx(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	return mi

## cfg keys: height (m), shirt, pants, shoes, skin, hair (Color or null=faceless),
## tie (Color or null), hat (bool), sheen (head roughness)
func build(cfg: Dictionary) -> void:
	var h := float(cfg.get("height", 1.7))
	_scale_h = h / 1.7
	var shirt: StandardMaterial3D = _m(cfg.get("shirt", Color(0.42, 0.48, 0.60)))
	var pants: StandardMaterial3D = _m(cfg.get("pants", Color(0.25, 0.27, 0.32)))
	var shoes: StandardMaterial3D = _m(cfg.get("shoes", Color(0.12, 0.12, 0.13)))
	var skin_c: Color = cfg.get("skin", Color(0.85, 0.72, 0.62))
	var skin: StandardMaterial3D = _m(skin_c, float(cfg.get("sheen", 0.8)))

	_root = Node3D.new()
	add_child(_root)
	_root.scale = Vector3.ONE * _scale_h
	_base_y = 0.0

	# pelvis + torso
	_bx(_root, Vector3(0.34, 0.15, 0.22), Vector3(0, 0.97, 0), pants)
	_torso = _bx(_root, Vector3(0.40, 0.52, 0.24), Vector3(0, 1.31, 0), shirt)
	# head
	_head = Node3D.new()
	_root.add_child(_head)
	_head.position = Vector3(0, 1.62, 0)
	var head_mesh := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.125
	hm.height = 0.25
	head_mesh.mesh = hm
	head_mesh.material_override = skin
	_head.add_child(head_mesh)
	head_mesh.position = Vector3(0, 0.06, 0)
	var hair_v: Variant = cfg.get("hair", null)
	if hair_v != null:
		var hair := MeshInstance3D.new()
		var hrm := SphereMesh.new()
		hrm.radius = 0.13
		hrm.height = 0.14
		hair.mesh = hrm
		hair.material_override = _m(hair_v)
		_head.add_child(hair)
		hair.position = Vector3(0, 0.13, 0.01)
	if bool(cfg.get("hat", false)):
		var brim := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.21
		bm.bottom_radius = 0.21
		bm.height = 0.02
		brim.mesh = bm
		brim.material_override = _m(Color(0.07, 0.07, 0.09), 0.6)
		_head.add_child(brim)
		brim.position = Vector3(0, 0.15, 0)
		var top := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 0.13
		tm.bottom_radius = 0.14
		tm.height = 0.17
		top.mesh = tm
		top.material_override = brim.material_override
		_head.add_child(top)
		top.position = Vector3(0, 0.24, 0)
	var tie_v: Variant = cfg.get("tie", null)
	if tie_v != null:
		_bx(_root, Vector3(0.09, 0.34, 0.02), Vector3(0, 1.36, -0.135), _m(tie_v, 0.7))
		_bx(_root, Vector3(0.14, 0.10, 0.015), Vector3(0, 1.50, -0.137), _m(Color(0.92, 0.92, 0.94), 0.6))

	# arms (pivot at shoulder)
	_arm_l = _limb(Vector3(0.255, 1.50, 0), Vector3(0.09, 0.56, 0.09), shirt)
	_arm_r = _limb(Vector3(-0.255, 1.50, 0), Vector3(0.09, 0.56, 0.09), shirt)
	# legs (pivot at hip), with a shin pivot for knee bend
	_thigh_l = _limb(Vector3(0.10, 0.92, 0), Vector3(0.13, 0.42, 0.13), pants)
	_thigh_r = _limb(Vector3(-0.10, 0.92, 0), Vector3(0.13, 0.42, 0.13), pants)
	_shin_l = _limb(Vector3(0, -0.44, 0), Vector3(0.11, 0.40, 0.11), pants, _thigh_l)
	_shin_r = _limb(Vector3(0, -0.44, 0), Vector3(0.11, 0.40, 0.11), pants, _thigh_r)
	_bx(_shin_l, Vector3(0.12, 0.07, 0.24), Vector3(0, -0.42, -0.05), shoes)
	_bx(_shin_r, Vector3(0.12, 0.07, 0.24), Vector3(0, -0.42, -0.05), shoes)

	# soft blob shadow to ground the character
	var blob := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.9, 0.9)
	blob.mesh = qm
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.42))
	g.set_color(1, Color(0, 0, 0, 0.0))
	grad.gradient = g
	bmat.albedo_texture = grad
	blob.material_override = bmat
	blob.rotation_degrees.x = -90
	add_child(blob)
	blob.position = Vector3(0, 0.03, 0)

func _limb(pivot_pos: Vector3, size: Vector3, mat: StandardMaterial3D, parent: Node3D = null) -> Node3D:
	var pivot := Node3D.new()
	(parent if parent != null else _root).add_child(pivot)
	pivot.position = pivot_pos
	_bx(pivot, size, Vector3(0, -size.y / 2.0 + 0.02, 0), mat)
	return pivot

func _process(delta: float) -> void:
	var gait := clampf(move_speed / 3.0, 0.0, 1.4)
	_phase += clampf(move_speed, 0.0, 7.0) * delta * 2.6
	_crouch_amt = move_toward(_crouch_amt, 1.0 if crouching else 0.0, 5.0 * delta)
	var swing := sin(_phase) * 0.55 * gait * (1.0 - 0.5 * _crouch_amt)
	var idle := sin(_phase * 0.0 + Time.get_ticks_msec() / 1000.0 * 1.7) * 0.015

	_thigh_l.rotation.x = swing - 0.85 * _crouch_amt
	_thigh_r.rotation.x = -swing - 0.85 * _crouch_amt
	_shin_l.rotation.x = maxf(0.0, -sin(_phase)) * 0.6 * gait + 1.1 * _crouch_amt
	_shin_r.rotation.x = maxf(0.0, sin(_phase)) * 0.6 * gait + 1.1 * _crouch_amt
	_arm_l.rotation.x = -swing * 0.8
	_arm_r.rotation.x = swing * 0.8
	_torso.rotation.x = 0.38 * _crouch_amt
	_head.rotation.x = -0.30 * _crouch_amt
	_root.position.y = (_base_y - 0.34 * _crouch_amt + absf(cos(_phase)) * 0.035 * gait + idle) * _scale_h
