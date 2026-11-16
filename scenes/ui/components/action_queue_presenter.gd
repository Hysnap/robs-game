# res://scenes/ui/components/action_queue_presenter.gd
class_name ActionQueuePresenter
extends RefCounted

## Emitted whenever the staged queue changes (item added, removed, reordered, or toggled)
signal queue_changed(display_lines: Array, selected_index: int)
signal directive_added(directive: Dictionary)
signal directive_removed(directive: Dictionary)

var _staged_directives: Array[Dictionary] = []
var _active_operative_id: String = ""

## Sets the active operative filter ("" shows all crew; a resident_id/slot_id filters to that operative)
func set_active_operative_filter(operative_id: String) -> void:
	_active_operative_id = operative_id.strip_edges()
	_notify_queue_changed(-1)

## Returns the active operative filter ID
func get_active_operative_filter() -> String:
	return _active_operative_id

## Returns matching indices into _staged_directives for the active operative filter
func _get_visible_indices() -> Array[int]:
	var indices: Array[int] = []
	for i in range(_staged_directives.size()):
		if _active_operative_id.is_empty():
			indices.append(i)
		else:
			var assignee := str(_staged_directives[i].get("assigned_to", _staged_directives[i].get("initiator_id", ""))).strip_edges()
			if assignee == _active_operative_id:
				indices.append(i)
	return indices

## Maps a visible list row index back to the underlying _staged_directives index
func _resolve_real_index(visible_idx: int) -> int:
	var visible := _get_visible_indices()
	if visible_idx < 0 or visible_idx >= visible.size():
		return -1
	return visible[visible_idx]

## Adds a newly committed directive to the staged queue buffer
func add_directive(directive: Dictionary) -> void:
	if not directive.has("is_selected"):
		directive["is_selected"] = true
	_staged_directives.append(directive)

	var assignee := str(directive.get("assigned_to", directive.get("initiator_id", ""))).strip_edges()
	if not _active_operative_id.is_empty() and not assignee.is_empty() and _active_operative_id != assignee:
		_active_operative_id = assignee

	directive_added.emit(directive)
	var visible := _get_visible_indices()
	_notify_queue_changed(visible.size() - 1)

## Moves a directive at visible `selected_idx` by `direction` (-1 for UP, +1 for DOWN)
## Reorders within the active operative's sequence (or full queue if unfiltered)
func move_directive(selected_idx: int, direction: int) -> int:
	var visible := _get_visible_indices()
	if selected_idx < 0 or selected_idx >= visible.size():
		return -1

	var target_visible_idx: int = selected_idx + direction
	if target_visible_idx < 0 or target_visible_idx >= visible.size():
		return selected_idx

	var real_a: int = visible[selected_idx]
	var real_b: int = visible[target_visible_idx]

	var temp := _staged_directives[real_a]
	_staged_directives[real_a] = _staged_directives[real_b]
	_staged_directives[real_b] = temp

	_notify_queue_changed(target_visible_idx)
	return target_visible_idx

## Removes the directive at visible `selected_idx`
func remove_directive(selected_idx: int) -> int:
	var real_idx := _resolve_real_index(selected_idx)
	if real_idx < 0:
		return -1

	var removed := _staged_directives[real_idx]
	_staged_directives.remove_at(real_idx)
	directive_removed.emit(removed)

	var visible := _get_visible_indices()
	var new_select: int = clampi(selected_idx, 0, visible.size() - 1)
	if visible.is_empty():
		new_select = -1

	_notify_queue_changed(new_select)
	return new_select

## Toggles the selection/commitment flag on a single visible directive
func toggle_selection(selected_idx: int) -> void:
	var real_idx := _resolve_real_index(selected_idx)
	if real_idx < 0:
		return
	var current_state: bool = _staged_directives[real_idx].get("is_selected", true)
	_staged_directives[real_idx]["is_selected"] = not current_state
	_notify_queue_changed(selected_idx)

## Toggles all visible directives: if all are selected, uncheck all; otherwise check all
func toggle_all() -> void:
	var visible := _get_visible_indices()
	if visible.is_empty():
		return

	var all_selected: bool = true
	for real_idx in visible:
		if not _staged_directives[real_idx].get("is_selected", true):
			all_selected = false
			break

	var target_state: bool = not all_selected
	for real_idx in visible:
		_staged_directives[real_idx]["is_selected"] = target_state

	_notify_queue_changed(-1)

## Extracts and clears directives marked ready for execution across all operatives, preserving unselected drafts
func consume_selected_directives() -> Array[Dictionary]:
	var to_execute: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []

	for d in _staged_directives:
		if d.get("is_selected", true):
			to_execute.append(d)
		else:
			remaining.append(d)

	_staged_directives = remaining
	_notify_queue_changed(-1)
	return to_execute

## Returns a duplicate of all staged directives (or filtered if operative_id is supplied)
func get_staged_directives(operative_id: String = "") -> Array[Dictionary]:
	var filter_id := operative_id.strip_edges()
	if filter_id.is_empty():
		return _staged_directives.duplicate(true)
	var out: Array[Dictionary] = []
	for d in _staged_directives:
		var assignee := str(d.get("assigned_to", d.get("initiator_id", ""))).strip_edges()
		if assignee == filter_id:
			out.append(d.duplicate(true))
	return out

## Clears all staged directives
func clear() -> void:
	_staged_directives.clear()
	_notify_queue_changed(-1)

## Returns the current visible queue item count
func size() -> int:
	return _get_visible_indices().size()

## Builds formatted display strings for ItemList or text-based presentation widgets
func get_display_lines() -> Array[String]:
	var display_queue: Array[String] = []
	var visible := _get_visible_indices()
	for v_idx in range(visible.size()):
		var d: Dictionary = _staged_directives[visible[v_idx]]
		var is_checked: bool = d.get("is_selected", true)
		var check_marker: String = "[✓]" if is_checked else "[  ]"

		var verb: String = str(d.get("verb", "ORDER"))
		var item: String = str(d.get("target_item", ""))
		var qty: float = float(d.get("amount", 0.0))
		var assignee: String = str(d.get("assigned_to", d.get("initiator_id", "Player")))
		var target_node: String = str(d.get("target_node_name", d.get("target_node_id", "")))
		if target_node.is_empty():
			target_node = str(d.get("target_node_id", ""))
		var contact: String = str(d.get("counterparty_id", ""))

		var line := "%d. %s [%s] %s x%.0f @ %s (Assigned: %s)" % [
			v_idx + 1, check_marker, verb, item, qty, target_node, assignee
		]
		if not contact.is_empty():
			line += " [Contact: %s]" % contact
		display_queue.append(line)
	return display_queue

func _notify_queue_changed(selected_index: int) -> void:
	queue_changed.emit(get_display_lines(), selected_index)