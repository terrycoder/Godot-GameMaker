@tool
class_name GMObjectDragLifecycleLedger
extends RefCounted

const FORMAL_SOURCE_SCRIPT_PATH := "res://addons/gm_editor/object_assembler/gm_object_library_list.gd"

static var _issued: Dictionary = {}
static var _registered_sources: Dictionary = {}
static var _sequence: int = 0

static func register_formal_source(source: Object) -> bool:
	if not _is_formal_source(source): return false
	_registered_sources[source.get_instance_id()] = weakref(source)
	return true

static func unregister_formal_source(source: Object) -> void:
	if source == null: return
	var source_id := source.get_instance_id()
	_registered_sources.erase(source_id)
	for nonce in _issued.keys():
		var fact: Dictionary = _issued[nonce]
		if int(fact.get("source_instance_id", 0)) == source_id: _issued.erase(nonce)

# Internal capability boundary: exact script identity, live tree registration,
# and the source's transient engine-callback gate must all agree.  There is no
# issue(source_id, content_id) API for arbitrary callers.
static func _issue_from_formal_drag(source: Object, definition: GMObjectDefinition) -> Dictionary:
	if not _registered_source_matches(source): return {"ok":false, "code":"object.drag_source_unregistered"}
	if definition == null or not source.call("_is_formal_drag_issue_active", definition):
		return {"ok":false, "code":"object.drag_lifecycle_not_active"}
	_sequence += 1
	var nonce := "gm.drag.v2.%s.%d.%d" % [str(source.get_instance_id()), definition.get_instance_id(), _sequence]
	_issued[nonce] = {
		"source_ref":weakref(source),
		"source_instance_id":source.get_instance_id(),
		"definition_ref":weakref(definition),
		"definition_instance_id":definition.get_instance_id(),
		"content_id":definition.content_id,
		"sequence":_sequence,
		"consumed":false
	}
	return {"ok":true, "nonce":nonce, "sequence":_sequence}

static func can_accept(data: Variant) -> bool:
	if not data is Dictionary: return false
	var nonce := str(data.get("lifecycle_nonce", ""))
	if nonce.is_empty() or not _issued.has(nonce): return false
	var fact: Dictionary = _issued[nonce]
	if bool(fact.get("consumed", false)): return false
	var source: Object = fact.get("source_ref").get_ref()
	var definition := fact.get("definition_ref").get_ref() as GMObjectDefinition
	if not _registered_source_matches(source) or definition == null: return false
	return source.get_instance_id() == int(data.get("source_control_instance_id", 0)) \
		and definition.get_instance_id() == int(fact.get("definition_instance_id", 0)) \
		and data.get("definition", null) == definition \
		and str(data.get("content_id", "")) == str(fact.get("content_id", "")) \
		and definition.content_id == str(fact.get("content_id", "")) \
		and str(data.get("evidence_path", "")) == "godot_control_drag_lifecycle"

static func consume(data: Dictionary) -> Dictionary:
	if not can_accept(data): return {"ok":false, "code":"object.drag_lifecycle_invalid"}
	var nonce := str(data.lifecycle_nonce)
	var fact: Dictionary = _issued[nonce]
	fact["consumed"] = true
	_issued[nonce] = fact
	return {"ok":true, "nonce":nonce, "sequence":fact.get("sequence", data.get("lifecycle_sequence", 0))}

static func reset_for_test() -> void:
	_issued.clear()
	_registered_sources.clear()
	_sequence = 0

static func _registered_source_matches(source: Object) -> bool:
	if not _is_formal_source(source): return false
	var source_id := source.get_instance_id()
	if not _registered_sources.has(source_id): return false
	return _registered_sources[source_id].get_ref() == source

static func _is_formal_source(source: Object) -> bool:
	return source != null and is_instance_valid(source) and source is Control and source.is_inside_tree() and source.get_script() != null and source.get_script().resource_path == FORMAL_SOURCE_SCRIPT_PATH
