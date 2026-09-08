@tool
class_name GMSignalSignature
extends RefCounted

## Godot 原生 signal 的局部签名快照。

static func enumerate(source: Object, signal_name: String = "") -> Dictionary:
	if source == null or not is_instance_valid(source): return {"ok": false, "code": "signal.source_released", "reason_zh": "信号源对象已释放。", "signals": []}
	var rows: Array[Dictionary] = []
	for raw in source.get_signal_list():
		var row: Dictionary = raw.duplicate(true)
		var name := str(row.get("name", ""))
		if not signal_name.is_empty() and name != signal_name: continue
		var args: Array = row.get("args", []) if row.get("args", []) is Array else []
		var params: Array[Dictionary] = []
		for index in args.size():
			var arg: Dictionary = args[index] if args[index] is Dictionary else {}
			params.append({"index": index, "name": str(arg.get("name", "arg%d" % index)), "type": int(arg.get("type", TYPE_NIL)), "class_name": str(arg.get("class_name", ""))})
		rows.append({"name": name, "args": params, "argument_count": params.size(), "source_class": source.get_class()})
	return {"ok": not rows.is_empty(), "code": "signal.enumerated" if not rows.is_empty() else "signal.missing", "reason_zh": "" if not rows.is_empty() else "找不到 Godot 局部信号：%s。" % signal_name, "signals": rows}

static func find_signal(source: Object, signal_name: String) -> Dictionary:
	var result := enumerate(source, signal_name)
	if not result.ok: return {}
	return result.signals[0]

static func enumerate_methods(target: Object, method_name: String = "") -> Dictionary:
	if target == null or not is_instance_valid(target): return {"ok": false, "code": "signal.target_released", "reason_zh": "信号目标对象已释放。", "methods": []}
	var rows: Array[Dictionary] = []
	for raw in target.get_method_list():
		var row: Dictionary = raw.duplicate(true)
		var name := str(row.get("name", ""))
		if not method_name.is_empty() and name != method_name: continue
		var args: Array = row.get("args", []) if row.get("args", []) is Array else []
		var default_args: Array = row.get("default_args", []) if row.get("default_args", []) is Array else []
		var flags := int(row.get("flags", 0))
		var default_count := mini(default_args.size(), args.size())
		rows.append({"name": name, "args": args, "argument_count": args.size(), "required_argument_count": args.size() - default_count, "default_args": default_args, "flags": flags, "vararg": (flags & METHOD_FLAG_VARARG) != 0, "return": row.get("return", {})})
	return {"ok": not rows.is_empty(), "code": "signal.methods_enumerated" if not rows.is_empty() else "signal.method_missing", "methods": rows}

static func compare(signal_info: Dictionary, method_info: Dictionary) -> Dictionary:
	var signal_args: Array = signal_info.get("args", []) if signal_info.get("args", []) is Array else []
	var method_args: Array = method_info.get("args", []) if method_info.get("args", []) is Array else []
	var signal_count := signal_args.size()
	var method_count := method_args.size()
	var flags := int(method_info.get("flags", 0))
	var vararg := (flags & METHOD_FLAG_VARARG) != 0
	var default_args: Array = method_info.get("default_args", []) if method_info.get("default_args", []) is Array else []
	var default_count := mini(default_args.size(), method_count)
	var min_method_count := method_count - default_count
	# Godot's Callable domain is [required, declared] for a fixed method and
	# [required, infinity) for a vararg method. Defaults live in method metadata,
	# not in individual arg dictionaries.
	var ok := signal_count >= min_method_count and (vararg or signal_count <= method_count)
	return {"ok": ok, "signal_argument_count": signal_count, "method_argument_count": method_count, "method_required_argument_count": min_method_count, "method_default_argument_count": default_count, "default_args": default_args, "vararg": vararg, "reason_zh": "" if ok else "Callable 参数不匹配：信号需要 %d 个参数，方法可接收 %d 个参数（必需 %d 个）。" % [signal_count, method_count, min_method_count]}
