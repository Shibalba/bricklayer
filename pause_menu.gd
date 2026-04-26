extends ColorRect

var resolutions: Dictionary = {
	0: Vector2i(1280, 720),
	1: Vector2i(1280, 800),
	2: Vector2i(1920, 1080),
	3: Vector2i(2560, 1440),
	4: Vector2i(3840, 2160),
}

const LINUX_DEFAULT_RESOLUTION := Vector2i(1280, 800)
const NON_LINUX_DEFAULT_RESOLUTION := Vector2i(1920, 1080)
const LINUX_DEFAULT_FPS := 40
const NON_LINUX_DEFAULT_FPS := 60
const WEB_DEFAULT_RESOLUTION := Vector2i(1280, 720)
const WEB_DEFAULT_FPS := 30

@onready var res_button = $SettingsPage/ResolutionRow/ResolutionButton
@onready var fps_button = $SettingsPage/FpsRow/FpsButton
@onready var render_distance_slider = $SettingsPage/RenderDistanceRow/RenderDistanceSlider
@onready var render_distance_label = $SettingsPage/RenderDistanceRow/Label
@onready var sdfgi_toggle = $SettingsPage/SdfgiToggle
@onready var ssao_toggle = $SettingsPage/SsaoToggle
@onready var ssil_toggle = $SettingsPage/SsilToggle
@onready var fog_toggle = $SettingsPage/FogToggle
@onready var shadows_toggle = $SettingsPage/ShadowsToggle
@onready var main_buttons = $MainButtons
@onready var settings_page = $SettingsPage
@onready var continue_button = $MainButtons/ContinueButton
@onready var settings_button = $MainButtons/SettingsButton
@onready var controls_button = $MainButtons/ControlsButton
@onready var controls_overlay = get_parent().get_node("ControlsOverlay")

func _ready():
	hide()
	_set_startup_defaults()
	_sync_graphics_toggles_from_environment()
	
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


func _set_startup_defaults() -> void:
	if _is_web_platform():
		_set_resolution_by_value(WEB_DEFAULT_RESOLUTION)
		_set_fps_by_value(WEB_DEFAULT_FPS)
		_set_graphics_defaults(false)
	elif _is_linux_platform():
		_set_resolution_by_value(LINUX_DEFAULT_RESOLUTION)
		_set_fps_by_value(LINUX_DEFAULT_FPS)
		_set_graphics_defaults(false)
	else:
		_set_resolution_by_value(NON_LINUX_DEFAULT_RESOLUTION)
		_set_fps_by_value(NON_LINUX_DEFAULT_FPS)


func _is_web_platform() -> bool:
	return OS.has_feature("web")


func _is_linux_platform() -> bool:
	return OS.get_name().to_lower().find("linux") != -1


func _set_resolution_by_value(resolution: Vector2i) -> void:
	var index := _find_resolution_index(resolution)
	if index == -1:
		return
	res_button.selected = index
	_apply_resolution(resolution)


func _find_resolution_index(resolution: Vector2i) -> int:
	for index in resolutions.keys():
		if resolutions[index] == resolution:
			return index
	return -1


func _set_fps_by_value(fps: int) -> void:
	var index := _find_option_index_by_text(fps_button, str(fps))
	if index == -1:
		return
	fps_button.selected = index
	set_max_fps_from_button()


func _find_option_index_by_text(button: OptionButton, text: String) -> int:
	for i in range(button.item_count):
		if button.get_item_text(i) == text:
			return i
	return -1


func _set_graphics_defaults(enabled: bool) -> void:
	sdfgi_toggle.button_pressed = enabled
	ssao_toggle.button_pressed = enabled
	ssil_toggle.button_pressed = enabled
	fog_toggle.button_pressed = enabled
	shadows_toggle.button_pressed = enabled
	_apply_graphics_from_toggles()


func _sync_graphics_toggles_from_environment() -> void:
	var world_env := _get_world_environment()
	if world_env and world_env.environment:
		sdfgi_toggle.button_pressed = world_env.environment.sdfgi_enabled
		ssao_toggle.button_pressed = world_env.environment.ssao_enabled
		ssil_toggle.button_pressed = world_env.environment.ssil_enabled
		fog_toggle.button_pressed = world_env.environment.fog_enabled

	var light := _get_directional_light()
	if light:
		shadows_toggle.button_pressed = light.shadow_enabled


func _apply_graphics_from_toggles() -> void:
	_on_sdfgi_toggle_toggled(sdfgi_toggle.button_pressed)
	_on_ssao_toggle_toggled(ssao_toggle.button_pressed)
	_on_ssil_toggle_toggled(ssil_toggle.button_pressed)
	_on_fog_toggle_toggled(fog_toggle.button_pressed)
	_on_shadows_toggle_toggled(shadows_toggle.button_pressed)


func _get_world_environment() -> WorldEnvironment:
	var scene := get_tree().current_scene
	if scene and scene.has_node("WorldEnvironment"):
		return scene.get_node("WorldEnvironment") as WorldEnvironment
	return null


func _get_directional_light() -> DirectionalLight3D:
	var scene := get_tree().current_scene
	if scene and scene.has_node("DirectionalLight3D"):
		return scene.get_node("DirectionalLight3D") as DirectionalLight3D
	return null


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
		if controls_overlay and controls_overlay.visible:
			controls_overlay.visible = false
			main_buttons.show()
			controls_button.grab_focus()
		elif settings_page.visible:
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
	if controls_overlay:
		controls_overlay.visible = false
	main_buttons.hide()
	settings_page.show()
	res_button.grab_focus()

func _on_controls_button_pressed():
	settings_page.hide()
	main_buttons.hide()
	if controls_overlay:
		controls_overlay.visible = true

func _on_back_button_pressed():
	# Hide settings, show main menu
	if controls_overlay:
		controls_overlay.visible = false
	settings_page.hide()
	main_buttons.show()
	settings_button.grab_focus()


func _on_fullscreen_toggle_toggled(toggled_on: bool):
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_resolution_selected(index: int):
	var resolution_size = resolutions.get(index, Vector2i(1280, 720))
	_apply_resolution(resolution_size, true)


func _apply_resolution(resolution_size: Vector2i, center_window: bool = false) -> void:
	get_viewport().set_content_scale_size(resolution_size)
	if _is_web_platform():
		return

	DisplayServer.window_set_size(resolution_size)

	if center_window:
		var screen_pos: Vector2i = DisplayServer.screen_get_position()
		var screen_size: Vector2i = DisplayServer.screen_get_size()
		var screen_center: Vector2 = Vector2(screen_pos) + Vector2(screen_size) * 0.5
		var window_half: Vector2 = Vector2(resolution_size) * 0.5
		var window_pos: Vector2i = Vector2i(screen_center - window_half)
		DisplayServer.window_set_position(window_pos)


func _on_sdfgi_toggle_toggled(toggled_on: bool) -> void:
	var world_env := _get_world_environment()
	if world_env and world_env.environment:
		world_env.environment.sdfgi_enabled = toggled_on


func _on_ssao_toggle_toggled(toggled_on: bool) -> void:
	var world_env := _get_world_environment()
	if world_env and world_env.environment:
		world_env.environment.ssao_enabled = toggled_on


func _on_ssil_toggle_toggled(toggled_on: bool) -> void:
	var world_env := _get_world_environment()
	if world_env and world_env.environment:
		world_env.environment.ssil_enabled = toggled_on


func _on_fog_toggle_toggled(toggled_on: bool) -> void:
	var world_env := _get_world_environment()
	if world_env and world_env.environment:
		world_env.environment.fog_enabled = toggled_on


func _on_shadows_toggle_toggled(toggled_on: bool) -> void:
	var light := _get_directional_light()
	if light:
		light.shadow_enabled = toggled_on

func toggle_pause(show_mouse_cursor: bool = true):
	var new_pause_state = !get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state
	
	if new_pause_state:
		# Reset to show main buttons every time we open the menu
		if controls_overlay:
			controls_overlay.visible = false
		main_buttons.show()
		settings_page.hide()
		continue_button.grab_focus()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if show_mouse_cursor else Input.MOUSE_MODE_CAPTURED
	else:
		if controls_overlay:
			controls_overlay.visible = false
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

func _on_render_distance_value_changed(value: float):
	render_distance_label.text = "Render Dst: %d" % int(value)
	var ground_generator = get_tree().current_scene.get_node("GroundGenerator")
	if ground_generator:
		ground_generator.render_distance = int(value)
