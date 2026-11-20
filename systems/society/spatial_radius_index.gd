# res://systems/society/spatial_radius_index.gd
class_name SpatialRadiusIndex
extends RefCounted

var _cell_size: float = 1500.0
var _buckets: Dictionary = {} # bucket_key (String) -> Dictionary[Vector2i, Array[Dictionary]]

func _init(cell_size_m: float = 1500.0) -> void:
	assert(cell_size_m > 0.0, "FATAL: [SpatialRadiusIndex] cell_size_m must be > 0.0.")
	_cell_size = cell_size_m

func _to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / _cell_size), floori(pos.y / _cell_size))

## Inserts an item at world-space position `pos` into the specified `bucket_key` partition
func insert(pos: Vector2, item: Variant, bucket_key: String = "") -> void:
	if not _buckets.has(bucket_key):
		_buckets[bucket_key] = {}
	var grid: Dictionary = _buckets[bucket_key]
	var cell: Vector2i = _to_cell(pos)
	if not grid.has(cell):
		grid[cell] = []
	grid[cell].append({
		"pos": pos,
		"item": item
	})

## Returns all items in `bucket_key` whose position lies within `radius_m` of `center_pos`
func query_radius(center_pos: Vector2, radius_m: float, bucket_key: String = "") -> Array:
	var results: Array = []
	if radius_m < 0.0 or not _buckets.has(bucket_key):
		return results

	var grid: Dictionary = _buckets[bucket_key]
	var center_cell: Vector2i = _to_cell(center_pos)
	var cell_span: int = maxi(1, ceili(radius_m / _cell_size))
	var radius_sq: float = radius_m * radius_m

	for dx in range(-cell_span, cell_span + 1):
		for dy in range(-cell_span, cell_span + 1):
			var cell_key := Vector2i(center_cell.x + dx, center_cell.y + dy)
			if not grid.has(cell_key):
				continue
			var entries: Array = grid[cell_key]
			for entry in entries:
				var e_pos: Vector2 = entry["pos"]
				if center_pos.distance_squared_to(e_pos) <= radius_sq:
					results.append(entry["item"])

	return results

## Returns all registered partition keys
func get_bucket_keys() -> Array:
	return _buckets.keys()

## Releases all indexed buckets and cell arrays
func clear() -> void:
	_buckets.clear()