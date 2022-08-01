extends Node


const ATTACHMENTS := {
	SinglePart.Bone.TORSO: "Torso",
	SinglePart.Bone.HEAD: "Head",
	SinglePart.Bone.R_ARM: "RArm",
	SinglePart.Bone.L_ARM: "LArm",
	SinglePart.Bone.R_HAND: "RHand",
	SinglePart.Bone.L_HAND: "LHand",
	SinglePart.Bone.R_LEG: "RLeg",
	SinglePart.Bone.L_LEG: "LLeg",
	SinglePart.Bone.R_FOOT: "RFoot",
	SinglePart.Bone.L_FOOT: "LFoot",
}

const SIZES := {
	"doll": 0.5,
	"shinmy": 0.75,
	"base": 1.0,
	"deka": 3.0,
}

@onready var _character: Character = get_parent()
@onready var _rig: Node3D = $"../Rig"
@onready var _skeleton: Skeleton3D = $"../Rig/Armature/Skeleton3D"
@onready var _capsule: CollisionShape3D = $"../Capsule"

@onready var _transparent_tex: Texture2D = preload("res://assets/textures/transparent.png")
@onready var _face_material: ShaderMaterial = preload("face/face_material.tres").duplicate()
@onready var _face_database: FaceDatabase = preload("res://resources/face_database.tres")

@export var appearance: Resource
var _appearance: Appearance :
	get:
		return appearance as Appearance

var _attached_parts := {}

var _base_camera_offset: float


func _ready():
	var face: MeshInstance3D = _skeleton.get_node("Face")
	face.material_override = _face_material

	load_appearance()


func _on_character_camera_updated(camera):
	_base_camera_offset = _character.camera.camera_offset
	_load_scale()


func _set_face_tex(uniform: StringName, texture: Texture2D):
	_face_material.set_shader_param(
		uniform, texture if texture != null else _transparent_tex
	)


func _load_face_part_style(method: StringName, style_name: StringName, uniform: StringName):
	var texture: Texture2D

	if style_name != "":
		var style: FacePartStyle = _face_database.call(method, style_name)
		if style:
			texture = style.texture
		else:
			push_error("Failed to load face style: %s" % style_name)

	_set_face_tex(uniform, texture)


func _load_face():
	# Eyebrow & mouth
	_load_face_part_style("get_eyebrow", _appearance.eyebrows, "brow_texture")
	_load_face_part_style("get_mouth", _appearance.mouth, "mouth_texture")

	# Eyes
	var eye_name := _appearance.eyes

	var eye_texture: Texture2D
	var shine_texture: Texture2D
	var overlay_texture: Texture2D

	if eye_name != "":
		var style: EyeStyle = _face_database.get_eye(eye_name)
		if style:
			eye_texture = style.eyes
			shine_texture = style.shine
			overlay_texture = style.overlay

			_face_material.set_shader_param(
				"eye_tint",
				_appearance.eyes_color if style.supports_recoloring else Color.WHITE
			)
		else:
			push_error("Failed to load eye style: %s" % eye_name)

	_set_face_tex("eye_texture", eye_texture)
	_set_face_tex("shine_texture", shine_texture)
	_set_face_tex("overlay_texture", overlay_texture)


func _attach_single(part_info: SinglePart, config: Dictionary) -> Node3D:
	const INIT_METHOD := &"_fh_initialize"

	var node: Node3D = load(SinglePart.BASE_PATH + part_info.scene_path).instantiate()

	var target_att: BoneAttachment3D = get_node(ATTACHMENTS[part_info.bone])
	target_att.add_child(node)
	node.transform = part_info.transform

	# Call AFTER _ready
	if node.has_method(INIT_METHOD):
		node.call(INIT_METHOD, config)

	return node


func attach(id: StringName, config: Dictionary):
	if _attached_parts.has(id):
		return

	var info = PartDatabase.get_part(id)
	if not info:
		push_error("Part not found: %s", id)
		return

	var attached_models: Array[Node3D] = []

	if info is SinglePart:
		attached_models.append(_attach_single(info, config))
	elif info is MultiPart:
		for single_part_info in info.parts:
			attached_models.append(_attach_single(single_part_info, config))

	_attached_parts[id] = attached_models


func detach(id: StringName):
	if not _attached_parts.has(id):
		return

	for model in _attached_parts[id]:
		model.queue_free()

	_attached_parts.erase(id)


func _load_parts():
	var part_ids = _appearance.attached_parts.keys()

	for part_id in part_ids:
		var config = _appearance.attached_parts[part_id]
		if not (config is Dictionary):
			config = {}

		attach(part_id, config)

	for part_id in _attached_parts.keys():
		if not part_ids.has(part_id):
			detach(part_id)


func _load_scale():
	var size_id := _appearance.size
	if not SIZES.has(size_id):
		push_error("Unknown size: %s", size_id)
		return

	var scale: float = SIZES[size_id]
	var scale_vec := Vector3.ONE * scale

	_rig.scale = scale_vec
	_rig.transform.origin = Vector3.ZERO

	_capsule.scale = scale_vec
	_capsule.transform.origin = Vector3.UP * _capsule.shape.height * scale / 2

	if _character.camera:
		_character.camera.camera_offset = _base_camera_offset * scale


func load_appearance():
	_load_face()
	_load_parts()
	_load_scale()
