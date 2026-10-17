extends Node


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    pass # Replace with function body.


# Inside systems/verb_router.gd (or wherever verbs are registered)
const CORE_VERBS_PATH: String = "res://data_modules/core/verbs/"

func autoload_verbs(active_variant: String = "") -> void:
    # 1. Scan core base verbs first
    _scan_and_mount_verbs(CORE_VERBS_PATH)
    
    # 2. If a variant defines custom or override verbs, scan those next
    if active_variant != "" and active_variant != "core":
        var variant_path = "res://data_modules/%s/verbs/" % active_variant
        if DirAccess.dir_exists_absolute(variant_path):
            _scan_and_mount_verbs(variant_path)