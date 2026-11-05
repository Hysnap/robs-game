# res://scenes/ui/components/action_queue_presenter.gd
class_name ActionQueuePresenter
extends RefCounted

## Emitted whenever the staged queue changes (item added, removed, reordered, or toggled)
signal queue_changed(display_lines: Array, selected_index: int)
signal directive_added(directive: Dictionary)
signal directive_removed(directive: Dictionary)

var _staged_directives: Array[Dictionary] = []

## Adds a newly committed directive to the staged queue buffer
func add_directive(directive: Dictionary) -> void:
	if not directive.has("is_selected"):
		directive["is_selected"] = true
	_staged_directives.append(directive)
	directive_added.emit(directive)
	_notify_queue_changed(_staged_directives.size() - 1)

## Moves a directive at `selected_idx` by `direction` (-1 for UP, +1 for DOWN)
## Returns the new index of the moved item, or -1 if no move occurred
func move_directive(selected_idx: int, direction: int) -> int:
	if selected_idx < 0 or selected_idx >= _staged_directives.size():
		return -1

	var target_idx: int = selected_idx + direction
	if target_idx < 0 or target_idx >= _staged_directives.size():
		return selected_idx

	var temp = _staged_directives[selected_idx]
	_staged_directives[selected_idx] = _staged_directives[target_idx]
	_staged_directives[target_idx] = temp

	_notify_queue_changed(target_idx)
	return target_idx

## Removes the directive at `selected_idx`
## Returns the suggested new selection index
func remove_directive(selected_idx: int) -> int:
	if selected_idx < 0 or selected_idx >= _staged_directives.size():
		return -1

	var removed = _staged_directives[selected_idx]
	_staged_directives.remove_at(selected_idx)
	directive_removed.emit(removed)

	var new_select: int = clampi(selected_idx, 0, _staged_directives.size() - 1)
	if _staged_directives.is_empty():
		new_select = -1

	_notify_queue_changed(new_select)
	return new_select

## Toggles the selection/commitment flag on a single directive
func toggle_selection(selected_idx: int) -> void:
	if selected_idx < 0 or selected_idx >= _staged_directives.size():
		return
	var current_state: bool = _staged_directives[selected_idx].get("is_selected", true)
	_staged_directives[selected_idx]["is_selected"] = not current_state
	_notify_queue_changed(selected_idx)

## Toggles all directives: if all are selected, uncheck all; otherwise check all
func toggle_all() -> void:
	if _staged_directives.is_empty():
		return

	var all_selected: bool = true
	for d in _staged_directives:
		if not d.get("is_selected", true):
			all_selected = false
			break

	var target_state: bool = not all_selected
	for d in _staged_directives:
		d["is_selected"] = target_state

	_notify_queue_changed(-1)

## Extracts and clears directives marked ready for execution, preserving unselected drafts
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

## Returns a duplicate of all staged directives
func get_staged_directives() -> Array[Dictionary]:
	return _staged_directives.duplicate(true)

## Clears all staged directives
func clear() -> void:
	_staged_directives.clear()
	_notify_queue_changed(-1)

## Returns the current queue item count
func size() -> int:
	return _staged_directives.size()

## Builds formatted display strings for ItemList or text-based presentation widgets
func get_display_lines() -> Array[String]:
	var display_queue: Array[String] = []
	for i in range(_staged_directives.size()):
		var d: Dictionary = _staged_directives[i]
		var is_checked: bool = d.get("is_selected", true)
		var check_marker: String = "[✓]" if is_checked else "[  ]"

		var verb: String = str(d.get("verb", "ORDER"))
		var item: String = str(d.get("target_item", ""))
		var qty: float = float(d.get("amount", 0.0))
		var assignee: String = str(d.get("assigned_to", d.get("initiator_id", "Player")))
		var target_node: String = str(d.get("target_node_id", ""))
		var contact: String = str(d.get("counterparty_id", ""))

		var line := "%d. %s [%s] %s x%.0f @ %s (Assigned: %s)" % [
			i + 1, check_marker, verb, item, qty, target_node, assignee
		]
		if not contact.is_empty():
			line += " [Contact: %s]" % contact
		display_queue.append(line)
	return display_queue

func _notify_queue_changed(selected_index: int) -> void:
	queue_changed.emit(get_display_lines(), selected_index)