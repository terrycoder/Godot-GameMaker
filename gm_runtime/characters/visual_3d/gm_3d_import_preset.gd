@tool
class_name GM3DImportPreset
extends Resource

const PRESET_SCHEMA := "gm.character.import_preset.v1"
const ASSET_FAMILIES := ["character", "environment", "prop", "animation", "vegetation"]
const MATERIAL_POLICIES := ["preserve", "platform_profile", "reject_missing"]
const COLLISION_POLICIES := ["none", "character_capsule", "static_mesh", "custom"]

@export var preset_schema: String = PRESET_SCHEMA
@export var preset_id: String = ""
@export var display_name_zh: String = ""
@export_enum("character", "environment", "prop", "animation", "vegetation") var asset_family: String = "character"
@export_range(0.0001, 100.0, 0.0001) var scale_meters_per_unit: float = 1.0
@export var pivot_policy: String = "root_origin"
@export_enum("preserve", "platform_profile", "reject_missing") var material_policy: String = "platform_profile"
@export_enum("none", "character_capsule", "static_mesh", "custom") var collision_policy: String = "none"
@export var generate_lod: bool = true
@export_range(0.0, 1.0, 0.01) var lod_screen_ratio: float = 0.35
@export var import_animation_clips: bool = true

func validate() -> Dictionary:
	var issues: Array[Dictionary] = []
	if preset_schema != PRESET_SCHEMA: issues.append(GMCharacter3DContract.failure("character.import_preset_schema_invalid", "导入 Preset 版本不受支持。"))
	if not GMCharacter3DContract.validate_id(preset_id, "import_preset").ok: issues.append(GMCharacter3DContract.failure("character.import_preset_id_invalid", "导入 Preset 缺少合法稳定标识。"))
	if display_name_zh.strip_edges().is_empty(): issues.append(GMCharacter3DContract.failure("character.import_preset_name_missing", "导入 Preset 缺少中文名称。"))
	if asset_family not in ASSET_FAMILIES: issues.append(GMCharacter3DContract.failure("character.import_preset_family_invalid", "导入 Preset 资产类别不受支持。"))
	if pivot_policy.strip_edges().is_empty(): issues.append(GMCharacter3DContract.failure("character.import_preset_pivot_missing", "导入 Preset 缺少 Pivot 策略。"))
	if material_policy not in MATERIAL_POLICIES: issues.append(GMCharacter3DContract.failure("character.import_preset_material_invalid", "导入 Preset 材质策略不受支持。"))
	if collision_policy not in COLLISION_POLICIES: issues.append(GMCharacter3DContract.failure("character.import_preset_collision_invalid", "导入 Preset 碰撞策略不受支持。"))
	for check in [GMCharacter3DContract.validate_positive(scale_meters_per_unit, "import_scale", "导入 Scale")]:
		if not check.ok: issues.append(check)
	if not is_finite(lod_screen_ratio) or lod_screen_ratio <= 0.0 or lod_screen_ratio > 1.0: issues.append(GMCharacter3DContract.failure("character.import_preset_lod_invalid", "LOD 屏幕比例必须在 (0,1] 内。"))
	return {"ok": issues.is_empty(), "issues": issues, "schema": PRESET_SCHEMA, "asset_family": asset_family, "stable_on_reimport": true}

func to_dict() -> Dictionary:
	return {"schema": PRESET_SCHEMA, "preset_id": preset_id, "display_name_zh": display_name_zh, "asset_family": asset_family, "scale_meters_per_unit": scale_meters_per_unit, "pivot_policy": pivot_policy, "material_policy": material_policy, "collision_policy": collision_policy, "generate_lod": generate_lod, "lod_screen_ratio": lod_screen_ratio, "import_animation_clips": import_animation_clips}

static func standard_presets() -> Array[GM3DImportPreset]:
	var result: Array[GM3DImportPreset] = []
	for row in [
		{"id":"gm.import.character.standard", "name":"角色标准导入", "family":"character", "pivot":"root_origin", "collision":"character_capsule"},
		{"id":"gm.import.environment.standard", "name":"环境标准导入", "family":"environment", "pivot":"ground_origin", "collision":"static_mesh"},
		{"id":"gm.import.prop.standard", "name":"Prop 标准导入", "family":"prop", "pivot":"authoring_origin", "collision":"custom"},
		{"id":"gm.import.animation.standard", "name":"动画标准导入", "family":"animation", "pivot":"root_origin", "collision":"none"},
		{"id":"gm.import.vegetation.standard", "name":"植被标准导入", "family":"vegetation", "pivot":"ground_origin", "collision":"none"},
	]:
		var preset := GM3DImportPreset.new()
		preset.preset_id = str(row.id); preset.display_name_zh = str(row.name); preset.asset_family = str(row.family); preset.pivot_policy = str(row.pivot); preset.collision_policy = str(row.collision)
		result.append(preset)
	return result
