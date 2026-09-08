@tool
class_name GMContentMigrationTable
extends Resource

@export var table_version: String = "1.0.0"
@export var entries: Array[GMContentMigrationEntry] = []

func resolve_id(value: String) -> Dictionary:
	var current := value
	var visited := {}
	var chain: Array[String] = [value]
	while true:
		if visited.has(current):
			return {"ok":false,"id":current,"chain":chain,"error_zh":"内容迁移别名形成循环：%s" % " -> ".join(chain)}
		visited[current] = true
		var next := ""
		for entry in entries:
			if entry != null and entry.status == "active" and entry.old_id == current:
				next = entry.new_id
				break
		if next.is_empty(): return {"ok":true,"id":current,"chain":chain,"migrated":chain.size() > 1}
		chain.append(next)
		current = next
	return {"ok":true,"id":current,"chain":chain,"migrated":chain.size() > 1}

func validate() -> Dictionary:
	var errors: Array[String] = []
	var old_ids := {}
	for entry in entries:
		if entry == null: errors.append("迁移表包含空条目。") ; continue
		if entry.old_id.strip_edges().is_empty() or entry.new_id.strip_edges().is_empty(): errors.append("迁移条目的旧 ID 和新 ID 不能为空。")
		if old_ids.has(entry.old_id): errors.append("迁移旧 ID 重复：%s" % entry.old_id)
		old_ids[entry.old_id] = true
		if entry.old_id == entry.new_id: errors.append("迁移条目不能把 ID 映射到自己：%s" % entry.old_id)
	for old_id in old_ids:
		var result := resolve_id(str(old_id))
		if not result.ok: errors.append(result.error_zh)
	return {"ok":errors.is_empty(),"errors_zh":errors}
