# res://scripts/world/district_overlay_renderer.gd
class_name DistrictOverlayRenderer
extends Node3D

const OVERLAY_ELEVATION_OFFSET := 0.12

const OVERLAY_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 fill_color : source_color = vec4(0.2, 0.5, 0.9, 0.45);
uniform int pattern_mode = 0; // 0 = NONE, 1 = FOG_HATCH, 2 = STALE_STRIPE, 3 = CONFLICT_STRIPE
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 col = fill_color.rgb;
	float alpha = fill_color.a;

	if (pattern_mode == 1) {
		// FOG_HATCH: subtle cross-hatch for unexplored / insufficient intel
		float d1 = abs(fract((world_pos.x + world_pos.z) * 0.18) - 0.5);
		float d2 = abs(fract((world_pos.x - world_pos.z) * 0.18) - 0.5);
		float hatch = step(min(d1, d2), 0.08);
		col = mix(col * 0.72, col * 1.15, hatch);
		alpha *= mix(0.78, 1.0, hatch);
	} else if (pattern_mode == 2) {
		// STALE_STRIPE: diagonal stripes signaling aged intel
		float stripe = step(fract((world_pos.x + world_pos.z) * 0.12), 0.35);
		col = mix(col * 0.65, vec3(0.90, 0.50, 0.14), stripe * 0.55);
		alpha *= mix(0.55, 1.0, stripe);
	} else if (pattern_mode == 3) {
		// CONFLICT_STRIPE: high-contrast diagonal stripes for multi-manager turf overlap
		float stripe = step(fract((world_pos.x - world_pos.z) * 0.14), 0.45);
		col = mix(col, vec3(0.98, 0.75, 0.15), stripe * 0.75);
		alpha *= mix(0.70, 1.0, stripe);
	}

	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.95);
}
"""

var _shader: Shader = null
var _overlay_meshes: Dictionary = {} # district_id -> MeshInstance3D
var _overlay_materials: Dictionary = {} # district_id -> ShaderMaterial
var _active_overlay_id: String = "NONE"

func _ready() -> void:
	_shader = Shader.new()
	_shader.code = OVERLAY_SHADER_CODE

func get_active_overlay_id() -> String:
	return _active_overlay_id

## Builds or refreshes overlay planes matching the ground meshes indexed by CityView
func bind_district_ground_nodes(district_ground_nodes: Dictionary) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = OVERLAY_SHADER_CODE

	for existing in _overlay_meshes.values():
		if is_instance_valid(existing):
			existing.queue_free()
	_overlay_meshes.clear()
	_overlay_materials.clear()

	for d_key in district_ground_nodes.keys():
		var district_id: String = str(d_key)
		var ground_node = district_ground_nodes[d_key]
		if not (ground_node is MeshInstance3D) or not is_instance_valid(ground_node):
			continue

		var aabb: AABB = ground_node.get_aabb()
		var plane := PlaneMesh.new()
		plane.size = Vector2(maxf(1.0, aabb.size.x), maxf(1.0, aabb.size.z))

		var mat := ShaderMaterial.new()
		mat.shader = _shader
		mat.set_shader_parameter("fill_color", Color(1.0, 1.0, 1.0, 0.0))
		mat.set_shader_parameter("pattern_mode", 0)

		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "Overlay_%s" % district_id
		mesh_inst.mesh = plane
		mesh_inst.material_override = mat
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_inst.position = Vector3(
			ground_node.position.x,
			ground_node.position.y + aabb.size.y * 0.5 + OVERLAY_ELEVATION_OFFSET,
			ground_node.position.z
		)
		mesh_inst.visible = false
		add_child(mesh_inst)

		_overlay_meshes[district_id] = mesh_inst
		_overlay_materials[district_id] = mat

## Applies normalized projection output from MapOverlayProjector.project_city_overlay()
func apply_projection(projection: Dictionary) -> void:
	_active_overlay_id = str(projection.get("overlay_id", "NONE")).to_upper()
	var mode: String = str(projection.get("mode", "NONE")).to_upper()
	var districts: Dictionary = projection.get("districts", {})

	if mode == "NONE" or _active_overlay_id == "NONE":
		for mesh_inst in _overlay_meshes.values():
			if is_instance_valid(mesh_inst):
				mesh_inst.visible = false
		return

	for d_key in _overlay_meshes.keys():
		var district_id: String = str(d_key)
		var mesh_inst: MeshInstance3D = _overlay_meshes[district_id]
		var mat: ShaderMaterial = _overlay_materials.get(district_id, null)
		if not is_instance_valid(mesh_inst) or mat == null:
			continue

		var d_proj: Dictionary = districts.get(district_id, {})
		if d_proj.is_empty() or not bool(d_proj.get("active", false)):
			mesh_inst.visible = false
			continue

		var col: Color = d_proj.get("fill_color", Color(0.4, 0.4, 0.4, 0.4))
		col.a = clampf(float(d_proj.get("fill_alpha", 0.45)), 0.0, 0.95)
		var pat_int: int = _pattern_token_to_int(str(d_proj.get("pattern_mode", "NONE")))

		mat.set_shader_parameter("fill_color", col)
		mat.set_shader_parameter("pattern_mode", pat_int)
		mesh_inst.visible = true

static func _pattern_token_to_int(pattern_token: String) -> int:
	match pattern_token.strip_edges().to_upper():
		"FOG_HATCH":
			return 1
		"STALE_STRIPE":
			return 2
		"CONFLICT_STRIPE":
			return 3
		_:
			return 0