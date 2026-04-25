extends CharacterBody3D

@export var mouse_sensitivity = 0.002
@export var stick_sensitivity = 1.5
@export var stick_look_speed = 2.5
@export var brick_scene: PackedScene = preload("res://brick.tscn")
@export var build_range: float = 2.0
@export var place_volume_db: float = -16.0
@export var remove_volume_db: float = -12.0
@export var footstep_interval: float = 0.32
@export var footstep_volume_db: float = -14.0
@export var footstep_pitch_min: float = 0.92
@export var footstep_pitch_max: float = 1.08
@export var jump_volume_db: float = -10.0
@export var landing_volume_db: float = -9.0
signal inventory_changed

const SLOT_COUNT = 10
const MAX_STACK = 64
var inventory: Array = []
var selected_slot: int = 0

@onready var camera = $Head/Camera3D
@onready var preview_brick = get_parent().get_node("PreviewBrick")

# PRELOAD ASSETS (Loads once at start, not every click)
@onready var place_sfx = preload("res://kick.wav")
@onready var remove_sfx = preload("res://swipe.wav")
@onready var footstep_sfx_c = preload("res://Steps_gravel-005.ogg")
@onready var footstep_sfx_d = preload("res://Steps_gravel-006.ogg")
@onready var footstep_sfx_a = preload("res://Steps_gravel-017.ogg")
@onready var footstep_sfx_b = preload("res://Steps_gravel-018.ogg")
@onready var landing_sfx = preload("res://Steps_gravel-019.ogg")
@onready var jump_sfx = preload("res://Steps_gravel-021.ogg")
@onready var anim_player = $AnimationPlayer

# CACHE THE BRICKS FOLDER (Faster and safer than get_tree)
@onready var bricks_folder = %Bricks

@onready var pause_menu = get_parent().get_node("CanvasLayer/PauseMenu")


const SPEED = 5.0
const JUMP_VELOCITY = 4.5
const BRICK_SIZE = 0.5
const HALF_BRICK = BRICK_SIZE * 0.5
var footstep_timer: float = 0.0
var footstep_player: AudioStreamPlayer
var footstep_sfx_list: Array[AudioStream] = []
var last_footstep_index: int = -1
var was_on_floor_last_frame: bool = false
var airborne_time: float = 0.0


func _snap_to_grid(pos: Vector3) -> Vector3:
	return Vector3(
		round(pos.x / BRICK_SIZE) * BRICK_SIZE,
		round(pos.y / BRICK_SIZE) * BRICK_SIZE,
		round(pos.z / BRICK_SIZE) * BRICK_SIZE
	)


func add_to_inventory(block_type: String) -> bool:
	# First: try to stack onto existing non-full slot of same type
	for i in SLOT_COUNT:
		if inventory[i] != null and inventory[i]["type"] == block_type and inventory[i]["count"] < MAX_STACK:
			inventory[i]["count"] += 1
			emit_signal("inventory_changed")
			return true
	# Second: find first empty slot
	for i in SLOT_COUNT:
		if inventory[i] == null:
			inventory[i] = {"type": block_type, "count": 1}
			emit_signal("inventory_changed")
			return true
	return false


func consume_from_slot() -> String:
	if inventory[selected_slot] == null:
		return ""
	var block_type: String = inventory[selected_slot]["type"]
	inventory[selected_slot]["count"] -= 1
	if inventory[selected_slot]["count"] <= 0:
		inventory[selected_slot] = null
	emit_signal("inventory_changed")
	return block_type


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	inventory.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		inventory[i] = null
	footstep_sfx_list = [footstep_sfx_c, footstep_sfx_d, footstep_sfx_a, footstep_sfx_b]
	footstep_player = AudioStreamPlayer.new()
	footstep_player.volume_db = footstep_volume_db
	add_child(footstep_player)
	was_on_floor_last_frame = is_on_floor()


func _input(event: InputEvent) -> void:
	# While menu is open, let active device control cursor visibility.
	if pause_menu and pause_menu.visible:
		if event is InputEventMouseMotion or event is InputEventMouseButton:
			if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	# During gameplay, keep mouse captured for FPS camera control.
	if get_tree().paused:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventKey:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event):
	if get_tree().paused:
		return

	if event is InputEventMouseMotion:
		# Rotate the whole player left/right
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Rotate ONLY the head up/down
		$Head.rotate_x(-event.relative.y * mouse_sensitivity)
		$Head.rotation.x = clamp($Head.rotation.x, -deg_to_rad(80), deg_to_rad(80))

	if event.is_action_pressed("left_click"):
		remove_block()

	if event.is_action_pressed("right_click"):
		place_block()

	# Inventory slot selection — keyboard 1-9 → slots 0-8, key 0 → slot 9
	var slot_keys = ["slot_1","slot_2","slot_3","slot_4","slot_5","slot_6","slot_7","slot_8","slot_9","slot_0"]
	for i in slot_keys.size():
		if event.is_action_pressed(slot_keys[i]):
			selected_slot = i
			emit_signal("inventory_changed")

	# Gamepad LB/RB cycle slots
	if event.is_action_pressed("slot_next"):
		selected_slot = (selected_slot + 1) % SLOT_COUNT
		emit_signal("inventory_changed")
	if event.is_action_pressed("slot_prev"):
		selected_slot = (selected_slot - 1 + SLOT_COUNT) % SLOT_COUNT
		emit_signal("inventory_changed")

	if event.is_action_pressed("ui_cancel"): # This is the ESC key or gamepad Start by default
		# Toggle pause menu
		if pause_menu:
			var opened_with_controller := event is InputEventJoypadButton or event is InputEventJoypadMotion
			pause_menu.toggle_pause(!opened_with_controller)


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		_play_jump_sound()
		was_on_floor_last_frame = false
		airborne_time = 0.0

	# --- GAMEPAD CAMERA LOOK ---
	# Poll analog stick input for camera control (frame-rate independent)
	var stick_x = Input.get_axis("look_horizontal_negative", "look_horizontal")
	var stick_y = Input.get_axis("look_vertical_negative", "look_vertical")
	if abs(stick_x) > 0 or abs(stick_y) > 0:
		# Use a dedicated rad/sec speed for analog look to avoid extremely tiny rotation.
		rotate_y(-stick_x * stick_look_speed * stick_sensitivity * delta)
		$Head.rotate_x(-stick_y * stick_look_speed * stick_sensitivity * delta)
		$Head.rotation.x = clamp($Head.rotation.x, -deg_to_rad(80), deg_to_rad(80))

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	if is_on_floor():
		if not was_on_floor_last_frame and airborne_time > 0.06:
			_play_landing_sound()
		airborne_time = 0.0
		was_on_floor_last_frame = true
	else:
		airborne_time += delta
		was_on_floor_last_frame = false

	_update_footsteps(delta)
	update_preview()


func _update_footsteps(delta: float) -> void:
	if get_tree().paused:
		return

	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var is_walking = is_on_floor() and horizontal_speed > 0.15

	if not is_walking:
		footstep_timer = 0.0
		return

	footstep_timer -= delta
	if footstep_timer > 0.0:
		return

	footstep_player.stream = _pick_footstep_stream()
	footstep_player.pitch_scale = randf_range(footstep_pitch_min, footstep_pitch_max)
	footstep_player.play()
	footstep_timer = footstep_interval


func _pick_footstep_stream() -> AudioStream:
	if footstep_sfx_list.is_empty():
		return null

	if footstep_sfx_list.size() == 1:
		last_footstep_index = 0
		return footstep_sfx_list[0]

	var next_index = randi_range(0, footstep_sfx_list.size() - 1)
	while next_index == last_footstep_index:
		next_index = randi_range(0, footstep_sfx_list.size() - 1)

	last_footstep_index = next_index
	return footstep_sfx_list[next_index]


func _play_jump_sound() -> void:
	var sfx = AudioStreamPlayer.new()
	sfx.stream = jump_sfx
	sfx.volume_db = jump_volume_db
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


func _play_landing_sound() -> void:
	var sfx = AudioStreamPlayer.new()
	sfx.stream = landing_sfx
	sfx.volume_db = landing_volume_db
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


func update_preview():
	if not preview_brick:
		return

	# Hide preview if selected slot is empty
	if inventory[selected_slot] == null:
		preview_brick.visible = false
		return

	var space_state = get_world_3d().direct_space_state
	var from = camera.global_transform.origin
	var to = from + (-camera.global_transform.basis.z * build_range)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self.get_rid()]

	var result = space_state.intersect_ray(query)
	if result:
		preview_brick.visible = true
		var n = result.normal.normalized()
		var target_center = result.collider.global_transform.origin
		preview_brick.global_position = target_center + n * (HALF_BRICK + 0.01)

		# Show only the targeted face by flattening one axis.
		if abs(n.x) > 0.5:
			preview_brick.scale = Vector3(0.02, 1.0, 1.0)
		elif abs(n.y) > 0.5:
			preview_brick.scale = Vector3(1.0, 0.02, 1.0)
		else:
			preview_brick.scale = Vector3(1.0, 1.0, 0.02)
	else:
		preview_brick.visible = false


func place_block():
	var block_type = consume_from_slot()
	if block_type == "":
		return

	var space_state = get_world_3d().direct_space_state
	var from = camera.global_transform.origin
	var to = from + (-camera.global_transform.basis.z * build_range)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self.get_rid()]

	var result = space_state.intersect_ray(query)

	if result:
		var spawn_pos = result.position + result.normal * HALF_BRICK
		var snapped_pos = _snap_to_grid(spawn_pos)

		var new_brick = brick_scene.instantiate()
		bricks_folder.add_child(new_brick)
		new_brick.global_position = snapped_pos
		new_brick.set_meta("block_type", block_type)

		# Apply material by block type
		var mesh = new_brick.find_child("MeshInstance3D")
		if mesh:
			var new_mat = StandardMaterial3D.new()
			if block_type == "wood":
				new_mat.albedo_color = Color(0.93, 0.91, 0.85)
			else: # ground_block
				new_mat.albedo_color = Color(0.4, 0.7, 0.25)
			new_mat.roughness = 1.0
			mesh.material_override = new_mat

		anim_player.play("place_brick")

		var sfx = AudioStreamPlayer.new()
		sfx.stream = place_sfx
		sfx.volume_db = place_volume_db
		get_tree().root.add_child(sfx)
		sfx.play()
		sfx.finished.connect(sfx.queue_free)
	else:
		# No surface hit — return the block to inventory
		add_to_inventory(block_type)


func remove_block():
	var space_state = get_world_3d().direct_space_state
	var from = camera.global_transform.origin
	var to = from + (-camera.global_transform.basis.z * build_range)
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self.get_rid()]

	var result = space_state.intersect_ray(query)

	if result:
		# Return block to inventory if it has a type tag (i.e. was placed by player)
		if result.collider.has_meta("block_type"):
			var block_type: String = result.collider.get_meta("block_type")
			add_to_inventory(block_type)
		elif result.collider.is_in_group("wood"):
			add_to_inventory("wood")
		elif result.collider.is_in_group("ground_block"):
			add_to_inventory("ground_block")

		anim_player.play("remove_brick")
		var sfx = AudioStreamPlayer.new()
		sfx.stream = remove_sfx
		sfx.volume_db = remove_volume_db
		get_tree().root.add_child(sfx)
		sfx.play()
		sfx.finished.connect(sfx.queue_free)
		result.collider.queue_free()


func _on_back_button_pressed() -> void:
	pass # Replace with function body.
