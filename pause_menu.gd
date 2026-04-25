extends ColorRect

var resolutions: Dictionary = {
	0: Vector2i(1280, 720),
	1: Vector2i(1920, 1080),
	2: Vector2i(2560, 1440),
	3: Vector2i(3840, 2160),
}

@onready var res_button = $SettingsPage/ResolutionRow/ResolutionButton
@onready var fps_button = $SettingsPage/FpsRow/FpsButton
@onready var main_buttons = $MainButtons
@onready var settings_page = $SettingsPage
@onready var continue_button = $MainButtons/ContinueButton
@onready var settings_button = $MainButtons/SettingsButton

func _ready():
	hide()
	
	# 1. Set the visual state of the dropdown (Index 1 is 1920x1080)
	res_button.selected = 1
	
	# 2. Apply the resolution immediately so the game starts at 1080p
	# Using the safe internal scaling method we discussed
	var default_res = resolutions[1]
	get_viewport().set_content_scale_size(default_res)

	# 3. Set the FPS cap dropdown default to 60
	fps_button.selected = 1
	set_max_fps_from_button()
	
	# Safety check: Only connect if the button was actually found
	if res_button:
		res_button.item_selected.connect(_on_resolution_selected)
	else:
		print("ERROR: ResolutionButton not found! Check your path in the script.")

	if fps_button:
		fps_button.item_selected.connect(_on_fps_selected)
	else:
		print("ERROR: FpsButton not found! Check your path in the script.")

	# Start with settings hidden
	settings_page.hide()
	main_buttons.show()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# Keep cursor mode aligned with the active input device while paused.
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	if event.is_action_pressed("menu_back"):
		if settings_page.visible:
			_on_back_button_pressed()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()

func set_max_fps_from_button() -> void:
	var fps_text = fps_button.get_item_text(fps_button.selected)
	var fps_value = int(fps_text)
	Engine.max_fps = fps_value
	print("Max FPS set to %d" % fps_value)

func _on_fps_selected(index: int):
	var fps_text = fps_button.get_item_text(index)
	var fps_value = int(fps_text)
	Engine.max_fps = fps_value
	print("Max FPS selected: %d" % fps_value)

# --- Navigation Logic ---

func _on_settings_button_pressed():
	# Hide the main menu, show settings
	main_buttons.hide()
	settings_page.show()
	res_button.grab_focus()

func _on_back_button_pressed():
	# Hide settings, show main menu
	settings_page.hide()
	main_buttons.show()
	settings_button.grab_focus()


func _on_fullscreen_toggle_toggled(toggled_on: bool):
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_resolution_selected(index: int):
	# 1. Get the resolution from our dictionary
	var size = resolutions[index]

	# 2. Tell the DisplayServer to change the window size
	DisplayServer.window_set_size(size)

	# 3. Center the window on the screen after resizing
	var screen_center = DisplayServer.screen_get_position() + (DisplayServer.screen_get_size() / 2)
	var window_pos = screen_center - (size / 2)
	DisplayServer.window_set_position(window_pos)

func toggle_pause(show_mouse_cursor: bool = true):
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state
	
	if new_pause_state:
		# Reset to show main buttons every time we open the menu
		main_buttons.show()
		settings_page.hide()
		continue_button.grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show_mouse_cursor else Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- Button Connections ---

func _on_continue_button_pressed():
	toggle_pause()

func _on_quit_button_pressed():
	get_tree().quit()

func _on_restart_button_pressed():
	# 1. Unpause the game engine first! 
	# If you don't do this, the new scene will start frozen.
	get_tree().paused = false

	# 2. Reload the scene (this clears the Bricks folder automatically)
	get_tree().reload_current_scene()
