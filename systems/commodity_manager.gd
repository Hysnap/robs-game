class_name CommodityManager extends RefCounted

static func load_hierarchical_commodities(root_dir_path: String) -> Dictionary:
    var registry: Dictionary = {}
    _scan_directory_recursive(root_dir_path, {}, registry)
    return registry

static func _scan_directory_recursive(current_path: String, inherited_traits: Dictionary, out_registry: Dictionary) -> void:
    var dir = DirAccess.open(current_path)
    if not dir:
        return

    # 1. Check if a local baseline exists in this folder to layer into inherited traits
    var local_base_path = current_path.path_join("_base.json")
    var current_scope_traits = inherited_traits.duplicate(true)
    
    if FileAccess.file_exists(local_base_path):
        var base_data = _read_json(local_base_path)
        _deep_merge_dict(current_scope_traits, base_data)

    # 2. Iterate directory contents
    dir.list_dir_begin()
    var file_name = dir.get_next()
    
    while file_name != "":
        if not file_name.begins_with("."):
            var full_path = current_path.path_join(file_name)
            
            if dir.current_is_dir():
                # Recurse down into sub-tier, passing down accumulated traits
                _scan_directory_recursive(full_path, current_scope_traits, out_registry)
            elif file_name.ends_with(".json") and file_name != "_base.json":
                # Leaf product found: merge stacked traits with specific overrides
                var leaf_data = _read_json(full_path)
                var final_product = current_scope_traits.duplicate(true)
                _deep_merge_dict(final_product, leaf_data)
                
                var item_id = final_product.get("id", file_name.get_basename().to_upper())
                final_product["id"] = item_id
                final_product["source_path"] = full_path
                out_registry[item_id] = final_product
                
        file_name = dir.get_next()
    dir.list_dir_end()

## Recursively merges source into target (allowing nested dictionaries to cascade)
static func _deep_merge_dict(target: Dictionary, source: Dictionary) -> void:
    for key in source.keys():
        if source[key] is Dictionary and target.get(key) is Dictionary:
            _deep_merge_dict(target[key], source[key])
        else:
            target[key] = source[key]

static func _read_json(path: String) -> Dictionary:
    var file = FileAccess.open(path, FileAccess.READ)
    if not file: return {}
    var json = JSON.new()
    if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
        return json.data
    return {}