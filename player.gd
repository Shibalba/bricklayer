extends CharacterBody3D

@export var mouse_sensitivity = 0.002
@export var stick_sensitivity = 1.5
@export var stick_look_speed = 2.5
@export var brick_scene: PackedScene = preload("res://brick.tscn")
@export var build_range: float = 10.0
var color_index: int = 0

@onready var camera = $Head/Camera3D
@onready var preview_brick = get_parent().get_node("PreviewBrick")

# PRELOAD ASSETS (Loads once at start, not every click)
@onready var dust_particles = preload("res://dust_cloud.tscn")
@onready var place_sfx = preload("res://click.wav")
@onready var anim_player = $AnimationPlayer

# CACHE THE BRICKS FOLDER (Faster and safer than get_tree)
@onready var bricks_folder = %Bricks

@onready var pause_menu = get_parent().get_node("CanvasLayer/PauseMenu")


const SPEED = 5.0
const JUMP_VELOCITY = 4.5
var current_color: Color = Color.DARK_RED


func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
		place_brick()

	if event.is_action_pressed("right_click"):
		remove_brick()

	#if event.is_action_pressed("ui_focus_next"): # Tab or add keys 1, 2, 3 to Input Map
		#current_color = Color(randf(), randf(), randf()) # Random color for fun

	if event.is_action_pressed("ui_focus_next"): # The TAB key or gamepad Y button
		var colors = [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW, Color.PURPLE]
		color_index += 1
		color_index = color_index % colors.size()
		current_color = colors[color_index]
		print("Switched to color #", color_index, ": ", current_color)

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
	update_preview()


func update_preview():
	# 1. Safety check: make sure the node actually exists
	if not preview_brick:
		return

	var space_state = get_world_3d().direct_space_state
	var mouse_pos = get_viewport().get_mouse_position()
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * build_range
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self.get_rid()]
	
	var result = space_state.intersect_ray(query)
	
	if result:
		preview_brick.visible = true
		var spawn_pos = result.position + result.normal * 0.5
		preview_brick.global_position = Vector3(round(spawn_pos.x), round(spawn_pos.y), round(spawn_pos.z))

		# 2. Safety check: Ensure the brick has a material to color
		if preview_brick.material_override == null:
			preview_brick.material_override = StandardMaterial3D.new()
			preview_brick.material_override.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		
		# 3. Apply the color safely
		var preview_color = current_color
		preview_color.a = 0.5 # Make it semi-transparent
		preview_brick.material_override.albedo_color = preview_color
	else:
		preview_brick.visible = false


func place_brick():
	var space_state = get_world_3d().direct_space_state
	var mouse_pos = get_viewport().get_mouse_position()

	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * build_range
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self.get_rid()]

	var result = space_state.intersect_ray(query)

	if result:
		var spawn_pos = result.position + result.normal * 0.5
		var snapped_pos = Vector3(round(spawn_pos.x), round(spawn_pos.y), round(spawn_pos.z))
		
		# 1. Instantiate and Add Brick to the container
		var new_brick = brick_scene.instantiate()
		bricks_folder.add_child(new_brick) # Uses the @onready variable from Step 1
		new_brick.global_position = snapped_pos

		# 2. Apply Color
		var mesh = new_brick.find_child("MeshInstance3D")
		if mesh:
			var new_mat = StandardMaterial3D.new()
			new_mat.albedo_color = current_color
			mesh.material_override = new_mat

		# 3. Spawn Particles (Juice!)
		var particles = dust_particles.instantiate()
		get_tree().root.add_child(particles)
		particles.global_position = snapped_pos

		anim_player.play("place_brick")

		# 4. Play Sound (Juice!)
		var sfx = AudioStreamPlayer.new()
		sfx.stream = place_sfx
		get_tree().root.add_child(sfx)
		sfx.play()
		sfx.finished.connect(sfx.queue_free)


func remove_brick():
	var space_state = get_world_3d().direct_space_state
	var mouse_pos = get_viewport().get_mouse_position()

	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * build_range
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self.get_rid()]

	var result = space_state.intersect_ray(query)

	if result:
		# result.collider is the Brick node we hit
		# We check if it's NOT the floor (we don't want to delete the floor!)
		if result.collider.name != "Floor":
			result.collider.queue_free() # This deletes the node


func _on_back_button_pressed() -> void:
	pass # Replace with function body.
