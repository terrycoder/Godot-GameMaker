class_name GMCombatContract
extends RefCounted

## P22 contract helpers. The helpers deliberately accept only JSON-safe native
## values. Runtime Vector2 values are converted to {x, y} before entering a
## contract; Nodes, paths and backend objects never cross this boundary.

const MAX_ID_LENGTH := 192
const MAX_TEXT_LENGTH := 512
const P19_INTENT_FIELDS := [
        "operation",
        "item_kind",
        "item_id",
        "quantity",
        "source_container_id",
        "target_container_id",
        "source_account_id",
        "target_account_id",
        "resource_id",
        "amount",
]

static func stable_id(value: Variant, allow_empty: bool = false) -> bool:
        if typeof(value) != TYPE_STRING:
                return false
        var text := str(value)
        if allow_empty and text.is_empty():
                return true
        if text.is_empty() or text != text.strip_edges() or text.length() > MAX_ID_LENGTH:
                return false
        for index in text.length():
                var code := text.unicode_at(index)
                if not ((code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57) or code in [46, 95, 45]):
                        return false
        return true

static func exact(value: Variant, fields: Array) -> bool:
        if not value is Dictionary or value.size() != fields.size():
                return false
        for field in fields:
                if not value.has(field):
                        return false
        return true

static func exact_field_types(value: Variant, string_fields: Array = [], number_fields: Array = [], boolean_fields: Array = [], array_fields: Array = [], dictionary_fields: Array = []) -> bool:
        if not value is Dictionary:
                return false
        for field in string_fields:
                if typeof(value.get(field, null)) != TYPE_STRING:
                        return false
        for field in number_fields:
                var number = value.get(field, null)
                if (typeof(number) != TYPE_INT and typeof(number) != TYPE_FLOAT) or not is_finite(float(number)):
                        return false
        for field in boolean_fields:
                if typeof(value.get(field, null)) != TYPE_BOOL:
                        return false
        for field in array_fields:
                if typeof(value.get(field, null)) != TYPE_ARRAY:
                        return false
        for field in dictionary_fields:
                if typeof(value.get(field, null)) != TYPE_DICTIONARY:
                        return false
        return true

static func unknown_fields(value: Variant, fields: Array, path: String) -> Array[String]:
        var errors: Array[String] = []
        if not value is Dictionary:
                errors.append("%s 必须是字典纯值。" % path)
                return errors
        for raw_key in value.keys():
                var key := str(raw_key)
                if not fields.has(key):
                        errors.append("%s 包含未知字段：%s。" % [path, key])
        return errors

static func pure(value: Variant, path: String = "$") -> Dictionary:
        var checked := GMStableData.validate_persistence(value, path)
        if checked.ok:
                return {"ok": true, "value": GMStableData.clone(value)}
        return {"ok": false, "code": "combat.pure_data_invalid", "reason_zh": "P22 合同只能携带可持久化纯数据。", "errors": checked.errors}

static func finite_nonnegative(value: Variant) -> bool:
        if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
                return false
        var number := float(value)
        return is_finite(number) and number >= 0.0

static func finite_positive(value: Variant) -> bool:
        if not finite_nonnegative(value):
                return false
        return float(value) > 0.0

static func finite_vector2(value: Variant, allow_zero: bool = true) -> bool:
        if not value is Dictionary or not exact(value, ["x", "y"]):
                return false
        var x = value.get("x", null)
        var y = value.get("y", null)
        if (typeof(x) != TYPE_INT and typeof(x) != TYPE_FLOAT) or (typeof(y) != TYPE_INT and typeof(y) != TYPE_FLOAT):
                return false
        if not is_finite(float(x)) or not is_finite(float(y)):
                return false
        if not allow_zero and is_zero_approx(float(x)) and is_zero_approx(float(y)):
                return false
        return true

static func vector2_native(value: Variant) -> Dictionary:
        if value is Vector2:
                return {"x": float(value.x), "y": float(value.y)}
        if value is Dictionary and value.has("x") and value.has("y"):
                var x = value.get("x", null)
                var y = value.get("y", null)
                if (typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT) and (typeof(y) == TYPE_INT or typeof(y) == TYPE_FLOAT) and is_finite(float(x)) and is_finite(float(y)):
                        return {"x": float(x), "y": float(y)}
        return {"x": 0.0, "y": 0.0}

static func text(value: Variant, allow_empty: bool = false) -> bool:
        if typeof(value) != TYPE_STRING:
                return false
        var candidate := str(value)
        if not allow_empty and candidate.strip_edges().is_empty():
                return false
        return candidate.length() <= MAX_TEXT_LENGTH and not candidate.contains("res://") and not candidate.contains("user://")

static func string_array(value: Variant, allow_empty: bool = true) -> bool:
        if not value is Array:
                return false
        for item in value:
                if not stable_id(item, allow_empty):
                        return false
        return true

static func p19_intent(value: Variant) -> Dictionary:
        if not value is Dictionary:
                return {"ok": false, "code": "combat.p19_intent_invalid", "reason_zh": "P19 交易意图必须是纯字典。"}
        var errors := unknown_fields(value, P19_INTENT_FIELDS, "p19_intent")
        var stable_fields := ["item_kind", "item_id", "source_container_id", "target_container_id", "source_account_id", "target_account_id", "resource_id"]
        for field in stable_fields:
                if value.has(field) and not stable_id(value.get(field)):
                        errors.append("P19 交易意图 %s 必须是稳定 ID。" % field)
        if value.has("operation") and (not value.operation is String or str(value.operation).strip_edges().is_empty()):
                errors.append("P19 交易意图 operation 不能为空。")
        if value.has("quantity") and (typeof(value.quantity) != TYPE_INT or int(value.quantity) <= 0):
                errors.append("P19 交易意图 quantity 必须是正整数。")
        if value.has("amount") and (typeof(value.amount) != TYPE_INT or int(value.amount) <= 0):
                errors.append("P19 交易意图 amount 必须是正整数。")
        var pure_check := pure(value, "$.p19_intent")
        if not pure_check.ok:
                errors.append_array(pure_check.errors)
        return {"ok": errors.is_empty(), "code": "combat.p19_intent_valid" if errors.is_empty() else "combat.p19_intent_invalid", "reason_zh": "" if errors.is_empty() else errors[0], "errors": errors}

static func failure(code: String, reason_zh: String, details: Dictionary = {}) -> Dictionary:
        var result := {"ok": false, "code": code, "reason_zh": reason_zh}
        if not details.is_empty():
                result["details"] = details.duplicate(true)
        return result

static func digest(value: Variant) -> String:
        return GMStableData.digest(value)
