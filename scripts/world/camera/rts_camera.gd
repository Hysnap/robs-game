# res://scripts/camera/rts_camera.gd
class_name RTSCamera3D
extends Node3D

signal district_clicked(block_id: String)
signal zoom_distance_changed(distance: float)

@export_group("Distance & Limits")
@export var min_distance: float = 30.0
@export var max_distance: float = 4000.0
@export var default_distance: float = 1000.0

@export_group("Angles & Orientation")
@export_range(10.0, 85.0, 1.0) var min_pitch_deg: float = 15.0
@export_range(10.0, 85.0, 1.0) var max_pitch_deg: float = 80.0
@export var default_pitch_deg: float = 58.0

@export_group("Speeds & Sensitivity")
@export var orbit_sensitivity: float = 0.005
@export var pan_sensitivity: float = 0.001
@export var key_pan_speed: float = 0.75
@export var zoom_factor: float = 0.15

var camera: Camera3D
var camera_target := Vector3.ZERO
var camera_distance := 1000.0
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(58.0)

var orbiting := false
var panning := false

func _ready() -> void:
	camera_distance = default_distance
	camera_pitch = deg_to_rad(default_pitch_deg)
	
	camera = get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		add_child(camera)
		
	camera.fov = 50.0
	camera.far = 8000.0
	camera.current = true
	update_transform()

func focus_on(target_pos: Vector3, distance: float = -1.0) -> void:
	camera_target = target_pos
	if distance > 0.0:
		camera_distance = clampf(distance, min_distance, max_distance)
	update_transform()

func update_transform() -> void:
	if camera == null:
		return

	var horizontal_distance := camera_distance * cos(camera_pitch)
	var height := camera_distance * sin(camera_pitch)

	camera.global_position = camera_target + Vector3(
		sin(camera_yaw) * horizontal_distance,
		height,
		cos(camera_yaw) * horizontal_distance
	)
	camera.look_at(camera_target)
	zoom_distance_changed.emit(camera_distance)

func _process(delta: float) -> void:
	var movement := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): movement.z -= 1.0
	if Input.is_key_pressed(KEY_S): movement.z += 1.0
	if Input.is_key_pressed(KEY_A): movement.x -= 1.0
	if Input.is_key_pressed(KEY_D): movement.x += 1.0

	if movement != Vector3.ZERO and camera != null:
		# Pan relative to the camera's current horizontal heading
		var forward := Vector3(-sin(camera_yaw), 0, -cos(camera_yaw)).normalized()
		var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw)).normalized()
		var move_dir := (forward * -movement.z + right * movement.x).normalized()

		var speed: float = camera_distance * key_pan_speed
		camera_target += move_dir * speed * delta
		update_transform()

func _unhandled_input(event: InputEvent) -> void:
	# 1. Mouse Drag (Orbit & Pan)
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if orbiting and camera != null:
			camera_yaw -= mm.relative.x * orbit_sensitivity
			camera_pitch = clampf(
				camera_pitch - mm.relative.y * orbit_sensitivity, 
				deg_to_rad(min_pitch_deg), 
				deg_to_rad(max_pitch_deg)
			)
			update_transform()
			get_viewport().set_input_as_handled()
		elif panning and camera != null:
			var right: Vector3 = camera.global_transform.basis.x
			var up: Vector3 = camera.global_transform.basis.y
			var pan_vector: Vector3 = (-right * mm.relative.x + up * mm.relative.y) * (camera_distance * pan_sensitivity)
			camera_target += pan_vector
			update_transform()
			get_viewport().set_input_as_handled()

	# 2. Mouse Buttons (Clicks & Zoom)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			orbiting = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			panning = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			camera_distance = max(camera_distance * (1.0 - zoom_factor), min_distance)
			update_transform()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			camera_distance = min(camera_distance * (1.0 + zoom_factor), max_distance)
			update_transform()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_handle_raycast_selection(mb.position)

func _handle_raycast_selection(screen_pos: Vector2) -> void:
	if camera == null:
		return

	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * (max_distance * 1.5)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)
	if result and result.collider:
		var hit: Node = result.collider
		# Check collider or parent for block_id metadata
		var block_id := ""
		if hit.has_meta("block_id"):
			block_id = str(hit.get_meta("block_id"))
		elif hit.get_parent() and hit.get_parent().has_meta("block_id"):
			block_id = str(hit.get_parent().get_meta("block_id"))

		if not block_id.is_empty():
			district_clicked.emit(block_id)
			get_viewport().set_input_as_handled()