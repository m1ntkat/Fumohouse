extends DebugMenu


var _character: Character
@export_node_path(RigidDynamicBody3D) var character: NodePath

var _horizontal_motion: HorizontalMotion
var _physical_motion: PhysicalMotion
var _stairs_motion: StairsMotion

var _state: RichTextLabel


func _init():
	menu_name = "character_debug"
	action = "debug_2"


func _ready():
	super._ready()

	_update_character()
	_horizontal_motion = _character.get_node_or_null("HorizontalMotion")
	_physical_motion = _character.get_node_or_null("PhysicalMotion")
	_stairs_motion = _character.get_node_or_null("StairsMotion")

	_state = add_entry("state", "State").contents

	add_entry("grounded", "Is Grounded")
	add_entry("airborne", "Airborne Time")
	add_entry("speed", "Speed")
	add_entry("walls", "Wall Contacts")


func _debug_draw():
	var pos := _character.global_position
	var eye_pos := pos + Vector3.UP * _character.camera.camera_offset

	# Forward direction
	DebugDraw.draw_line(eye_pos, eye_pos - _character.global_transform.basis.z, Color.AQUA)

	# Grounding status
	if _character.is_grounded:
		DebugDraw.draw_line(pos, pos + _character.ground_normal, Color.GREEN)
	else:
		DebugDraw.draw_marker(pos, Color.RED)

	# Walls
	for wall_info in _character.walls:
		DebugDraw.draw_line(
			wall_info.point,
			wall_info.point + wall_info.normal,
			Color.WHITE
		)

	# Velocities
	if _horizontal_motion:
		var top_speed := _horizontal_motion.movement_speed

		DebugDraw.draw_line(pos, pos + _character.velocity / top_speed, Color.BLUE)

	# Stairs
	if _stairs_motion and _stairs_motion._found_stair:
		const STAIRS_AXIS_LEN := 0.25
		var target := _stairs_motion._end_position

		DebugDraw.draw_marker(_stairs_motion._begin_position, Color.AQUA)
		DebugDraw.draw_marker(target, Color.AQUA)

		DebugDraw.draw_line(
			target, target + _stairs_motion._wall_tangent * STAIRS_AXIS_LEN, Color.RED
		)

		DebugDraw.draw_line(
			target, target + _stairs_motion._slope_normal * STAIRS_AXIS_LEN, Color.GREEN
		)

		DebugDraw.draw_line(
			target, target + _stairs_motion._motion_vector * STAIRS_AXIS_LEN, Color.BLUE
		)


func _process(_delta: float):
	_state.clear()

	# State
	var states := Character.CharacterState.keys()

	for idx in states.size():
		if idx == 0: # NONE
			continue

		var state_name: String = states[idx]

		_state.push_color(Color.GREEN \
				if _character.is_state(Character.CharacterState[state_name]) \
				else Color.RED)

		_state.append_text(state_name)
		_state.pop()

		if idx != states.size() - 1:
			_state.newline()

	# Other
	set_val("grounded", "Yes" if _character.is_grounded else "No")
	set_val("airborne", "%.3f sec" % _physical_motion._airborne_time if _physical_motion else "???")

	var speed_str := """Total: %.3f m/s
HorizontalMotion: %.3f m/s
PhysicalMotion: %.3f m/s""" % [
		_character.velocity.length(),
		_horizontal_motion._velocity.length() if _horizontal_motion else 0.0,
		_physical_motion._velocity.length() if _physical_motion else 0.0,
	]

	set_val("speed", speed_str)
	set_val("walls", str(_character.walls.size()))

	_debug_draw()


func _update_character():
	if not is_inside_tree():
		return

	if not character.is_empty():
		_character = get_node(character) as Character