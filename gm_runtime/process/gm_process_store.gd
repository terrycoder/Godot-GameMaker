class_name GMProcessStore
extends RefCounted

## The only persisted Process source. It delegates generic storage and snapshot
## validation to the existing GMStore v3 contract.

signal backend_rebound(old_backend: GMStore, new_backend: GMStore)

const STORE_ID := "gm.store.process"
const STORE_SCHEMA := "gm.process.store.v1"
const CLOCK_KEY := "clock:logical"
const RECORD_KIND_INDEX := "gm.process.index.record_kind"
const STATE_INDEX := "gm.process.index.state"

var backend: GMStore
var _world: RefCounted
var _world_listener: Callable
var _world_prepare: Callable
var _world_commit: Callable

func _init(p_backend: GMStore = null) -> void:
	backend = p_backend if p_backend != null else GMStore.new(STORE_ID, STORE_SCHEMA)
	_ensure_backend_contract()

func configuration_check() -> Dictionary:
	if backend == null or not is_instance_valid(backend): return _failure("process.store_missing", "Process Store 后端不存在。")
	if backend.store_id != STORE_ID or backend.schema_version != STORE_SCHEMA:
		return _failure("process.store_identity_invalid", "Process Store 必须使用唯一固定身份和Schema。")
	return {"ok": true, "store_id": STORE_ID, "schema_version": STORE_SCHEMA}

func put_definition(definition: GMProcessDefinition) -> Dictionary:
	if definition == null: return _failure("process.definition_missing", "ProcessDefinition 不存在。")
	var validation := definition.validate()
	if not validation.ok: return {"ok": false, "code": "process.definition_invalid", "reason_zh": "ProcessDefinition 验证失败。", "errors": validation.errors}
	var key := _definition_key(definition.definition_id, definition.revision)
	var existing := backend.read(key)
	var row := definition.to_native()
	row["record_kind"] = "definition"
	row["state"] = "definition"
	if not existing.is_empty():
		if GMStableData.canonical_json(existing) == GMStableData.canonical_json(row): return {"ok": true, "duplicate": true, "key": key, "version": backend.version}
		return _failure("process.definition_revision_conflict", "同一 ProcessDefinition revision 已存在不同内容。", {"key": key})
	return backend.put(key, row)

func get_definition(definition_id: String, definition_revision: int = -1) -> GMProcessDefinition:
	var candidates: Array = []
	for key in backend.query_index(RECORD_KIND_INDEX, "definition"):
		var row := backend.read(str(key))
		if str(row.get("definition_id", "")) != definition_id: continue
		var revision := int(row.get("revision", 0))
		if definition_revision >= 0 and revision != definition_revision: continue
		row.erase("record_kind")
		row.erase("state")
		var parsed := GMProcessDefinition.from_native(row, true)
		if parsed.ok: candidates.append(parsed.definition)
	if candidates.is_empty(): return null
	candidates.sort_custom(func(left: GMProcessDefinition, right: GMProcessDefinition): return left.revision < right.revision)
	return candidates.back()

func put_instance(instance: GMProcessInstance) -> Dictionary:
	return _put_instance_and_clock(instance, null)

func put_runtime_state(instance: GMProcessInstance, clock: GMProcessClock) -> Dictionary:
	return _put_instance_and_clock(instance, clock)

func get_instance(instance_id: String) -> GMProcessInstance:
	if not backend.has(_instance_key(instance_id)): return null
	var row := backend.read(_instance_key(instance_id))
	row.erase("record_kind")
	var parsed := GMProcessInstance.from_native(row, true)
	return parsed.instance if parsed.ok else null

func instance_projection() -> Array:
	var rows: Array = []
	for key in backend.query_index(RECORD_KIND_INDEX, "instance"):
		var instance := get_instance(str(key).trim_prefix("instance:"))
		if instance != null: rows.append(instance.to_native())
	return rows

func get_clock() -> GMProcessClock:
	if not backend.has(CLOCK_KEY): return null
	var row := backend.read(CLOCK_KEY)
	if str(row.get("record_kind", "")) != "clock": return null
	var parsed := GMProcessClock.from_native(row.get("clock", {}), true)
	return parsed.clock if parsed.ok else null

func put_clock(clock: GMProcessClock) -> Dictionary:
	if clock == null: return _failure("process.clock_missing", "Process Store 不能写入空逻辑时钟。")
	var validation := clock.validate()
	if not validation.ok: return validation
	return backend.put(CLOCK_KEY, _clock_row(clock))

func snapshot() -> Dictionary:
	return backend.snapshot()

func restore_snapshot(value: Dictionary) -> Dictionary:
	var boundary := _new_backend()
	var restored := boundary.restore_snapshot(value)
	if not restored.ok: return {"ok": false, "code": "process.store_boundary_invalid", "reason_zh": "Process Store 快照未通过GMStore v3严格边界。", "details": restored}
	var definitions: Dictionary = {}
	var instance_rows: Array = []
	var clock_value: GMProcessClock = null
	for key in boundary.keys():
		var row := boundary.read(key)
		var kind := str(row.get("record_kind", ""))
		if kind == "definition":
			row.erase("record_kind")
			row.erase("state")
			var definition_result := GMProcessDefinition.from_native(row, true)
			if not definition_result.ok: return _failure("process.store_definition_invalid", "Process Store 中的 Definition 无效。", definition_result)
			var definition: GMProcessDefinition = definition_result.definition
			var expected_key := _definition_key(definition.definition_id, definition.revision)
			if str(key) != expected_key: return _failure("process.store_definition_key_invalid", "Definition 存储键与稳定版本身份不一致。", {"key": key, "expected": expected_key})
			definitions["%s|%d" % [definition.definition_id, definition.revision]] = true
		elif kind == "instance":
			row.erase("record_kind")
			var instance_result := GMProcessInstance.from_native(row, true)
			if not instance_result.ok: return _failure("process.store_instance_invalid", "Process Store 中的 Instance 无效。", instance_result)
			instance_rows.append(instance_result.instance)
		elif kind == "clock":
			if str(key) != CLOCK_KEY or clock_value != null: return _failure("process.store_clock_invalid", "Process Store 只能包含一个逻辑时钟记录。")
			var clock_result := GMProcessClock.from_native(row.get("clock", {}), true)
			if not clock_result.ok: return _failure("process.store_clock_invalid", "Process Store 逻辑时钟记录无效。", clock_result)
			clock_value = clock_result.clock
		else:
			return _failure("process.store_record_kind_invalid", "Process Store 含未知记录类型。", {"key": key, "record_kind": kind})
	for instance in instance_rows:
		var identity := "%s|%d" % [instance.definition_id, instance.definition_revision]
		if not definitions.has(identity): return _failure("process.store_instance_definition_missing", "ProcessInstance 引用了不存在的Definition revision。", {"instance_id": instance.instance_id})
		var definition := _definition_from_backend(boundary, instance.definition_id, instance.definition_revision)
		if definition == null or definition.duration_units != instance.progress.required_units:
			return _failure("process.store_instance_definition_mismatch", "ProcessInstance 的进度定义与Definition revision不一致。", {"instance_id": instance.instance_id})
	var old_backend := backend
	backend = boundary
	_ensure_backend_contract()
	backend_rebound.emit(old_backend, backend)
	return {"ok": true, "store_id": STORE_ID, "record_count": backend.keys().size(), "clock_present": clock_value != null}

func attach_to_world(world: RefCounted) -> Dictionary:
	if world == null or not is_instance_valid(world): return _failure("process.world_missing", "Process Store 绑定需要有效世界。")
	if world == _world:
		return {"ok": true, "duplicate": true, "store_id": STORE_ID, "world_id": str(world.get("world_id"))}
	for method_name in ["add_store", "register_store_replacement_listener", "unregister_store_replacement_listener", "register_atomic_restore_participant", "unregister_atomic_restore_participant"]:
		if not world.has_method(method_name): return _failure("process.world_interface_missing", "世界缺少 Process 原子恢复绑定接口。", {"method": method_name})
	var world_stores: Dictionary = world.get("stores") if _has_property(world, "stores") else {}
	var current: Variant = world_stores.get(STORE_ID, null)
	if current == null:
		var validation := _validate_backend_candidate(backend)
		if not validation.ok: return validation
		current = backend if _world == null else validation.backend
		var added: Dictionary = world.add_store(current)
		if not added.ok: return added
	elif not current is GMStore:
		return _failure("process.world_store_invalid", "世界中的Process Store后端类型无效。")
	else:
		var validation := _validate_backend_candidate(current)
		if not validation.ok: return validation
	var listener := Callable(self, "_on_world_store_replaced")
	var prepare := Callable(self, "_prepare_atomic_world_restore")
	var commit := Callable(self, "_commit_atomic_world_restore")
	var listener_result: Dictionary = world.register_store_replacement_listener(listener)
	if not listener_result.ok: return listener_result
	var participant_result: Dictionary = world.register_atomic_restore_participant(prepare, commit)
	if not participant_result.ok:
		world.unregister_store_replacement_listener(listener)
		return participant_result
	_disconnect_world_bindings()
	_world = world
	_world_listener = listener
	_world_prepare = prepare
	_world_commit = commit
	var old_backend := backend
	backend = current
	_ensure_backend_contract()
	if old_backend != backend: backend_rebound.emit(old_backend, backend)
	return {"ok": true, "store_id": STORE_ID, "world_id": str(world.get("world_id")), "participant_count": int(participant_result.get("participant_count", 0))}

func detach_from_world() -> void:
	if _world == null:
		_disconnect_world_bindings()
		return
	var detached := _validate_backend_candidate(backend)
	_disconnect_world_bindings()
	_world = null
	if not detached.ok: return
	var old_backend := backend
	backend = detached.backend
	_ensure_backend_contract()
	if old_backend != backend: backend_rebound.emit(old_backend, backend)

func _put_instance_and_clock(instance: GMProcessInstance, clock: GMProcessClock) -> Dictionary:
	if instance == null: return _failure("process.instance_missing", "ProcessInstance 不存在。")
	var validation := instance.validate()
	if not validation.ok: return {"ok": false, "code": "process.instance_invalid", "reason_zh": "ProcessInstance 验证失败。", "errors": validation.errors}
	var definition := get_definition(instance.definition_id, instance.definition_revision)
	if definition == null: return _failure("process.instance_definition_missing", "ProcessInstance 引用的Definition revision不存在。")
	if definition.duration_units != instance.progress.required_units: return _failure("process.instance_definition_mismatch", "ProcessInstance 进度定义与Definition不一致。")
	if clock != null:
		var clock_check := clock.validate()
		if not clock_check.ok: return clock_check
		if clock.now() < instance.progress.last_clock_value: return _failure("process.clock_behind_instance", "Process Store 逻辑时钟不得早于实例进度。")
	var staged := _new_backend()
	var stage_result := staged.restore_snapshot(backend.snapshot())
	if not stage_result.ok: return {"ok": false, "code": "process.store_stage_failed", "reason_zh": "Process Store 无法建立原子写入暂存区。", "details": stage_result}
	var row := instance.to_native()
	row["record_kind"] = "instance"
	var instance_write := staged.put(_instance_key(instance.instance_id), row)
	if not instance_write.ok: return instance_write
	if clock != null:
		var clock_write := staged.put(CLOCK_KEY, _clock_row(clock))
		if not clock_write.ok: return clock_write
	var committed := backend.restore_snapshot(staged.snapshot())
	if not committed.ok: return {"ok": false, "code": "process.store_atomic_commit_failed", "reason_zh": "Process Store 原子写入提交失败，原状态保持不变。", "details": committed}
	return {"ok": true, "store_id": STORE_ID, "instance_id": instance.instance_id, "version": backend.version, "clock": clock.to_native() if clock != null else {}}

func _new_backend() -> GMStore:
	var result := GMStore.new(STORE_ID, STORE_SCHEMA)
	result.create_index(RECORD_KIND_INDEX, "record_kind")
	result.create_index(STATE_INDEX, "state")
	return result

func _ensure_backend_contract() -> void:
	if backend == null: return
	if backend.store_id.is_empty(): backend.store_id = STORE_ID
	if backend.schema_version.is_empty(): backend.schema_version = STORE_SCHEMA
	if not backend.indexes.has(RECORD_KIND_INDEX): backend.create_index(RECORD_KIND_INDEX, "record_kind")
	if not backend.indexes.has(STATE_INDEX): backend.create_index(STATE_INDEX, "state")

func _definition_from_backend(source: GMStore, definition_id: String, revision: int) -> GMProcessDefinition:
	var key := _definition_key(definition_id, revision)
	var row := source.read(key)
	if row.is_empty(): return null
	row.erase("record_kind")
	row.erase("state")
	var parsed := GMProcessDefinition.from_native(row, true)
	return parsed.definition if parsed.ok else null

func _on_world_store_replaced(world: RefCounted) -> void:
	if world != _world: return
	var world_stores: Dictionary = world.get("stores") if _has_property(world, "stores") else {}
	var candidate: Variant = world_stores.get(STORE_ID, null)
	if candidate is GMStore and candidate.store_id == STORE_ID and candidate.schema_version == STORE_SCHEMA:
		var old_backend := backend
		backend = candidate
		_ensure_backend_contract()
		if old_backend != backend: backend_rebound.emit(old_backend, backend)

func _prepare_atomic_world_restore(_snapshot: Dictionary, staged_stores: Dictionary) -> Dictionary:
	var candidate: Variant = staged_stores.get(STORE_ID, null)
	if not candidate is GMStore:
		return _failure("process.restore_store_missing", "世界恢复候选缺少 Process Store。")
	var validation := _validate_backend_candidate(candidate)
	if not validation.ok:
		return _failure("process.restore_candidate_invalid", "Process Store 世界恢复候选未通过语义验证。", validation)
	return {"ok": true, "prepared": {"backend": candidate, "clock": validation.get("clock")}}

func _commit_atomic_world_restore(prepared: Dictionary, world: RefCounted) -> void:
	if world != _world: return
	var candidate: Variant = prepared.get("backend", null)
	if not candidate is GMStore: return
	var old_backend := backend
	backend = candidate
	_ensure_backend_contract()
	if old_backend != backend: backend_rebound.emit(old_backend, backend)

func _validate_backend_candidate(candidate: GMStore) -> Dictionary:
	if candidate == null or not is_instance_valid(candidate): return _failure("process.world_store_invalid", "世界中的Process Store后端类型无效。")
	var detached := GMProcessStore.new()
	var restored := detached.restore_snapshot(candidate.snapshot())
	if not restored.ok: return restored
	return {"ok": true, "backend": detached.backend, "clock": detached.get_clock()}

func _disconnect_world_bindings() -> void:
	if _world != null and _world_listener.is_valid() and _world.has_method("unregister_store_replacement_listener"):
		_world.unregister_store_replacement_listener(_world_listener)
	if _world != null and _world_prepare.is_valid() and _world_commit.is_valid() and _world.has_method("unregister_atomic_restore_participant"):
		_world.unregister_atomic_restore_participant(_world_prepare, _world_commit)
	_world_listener = Callable()
	_world_prepare = Callable()
	_world_commit = Callable()

func _has_property(value: Object, property_name: String) -> bool:
	for property in value.get_property_list():
		if str(property.get("name", "")) == property_name: return true
	return false

static func _definition_key(definition_id: String, revision: int) -> String:
	return "definition:%s:%d" % [definition_id, revision]

static func _instance_key(instance_id: String) -> String:
	return "instance:%s" % instance_id

static func _clock_row(clock: GMProcessClock) -> Dictionary:
	return {"record_kind": "clock", "state": "clock", "clock": clock.to_native()}

static func _failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
	var result := {"ok": false, "code": code, "reason_zh": reason_zh}
	if not details.is_empty(): result["details"] = details
	return result
