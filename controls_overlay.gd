extends ColorRect

@onready var keyboard_label = $Panel/Margin/Content/Columns/KeyboardColumn/KeyboardText
@onready var gamepad_label = $Panel/Margin/Content/Columns/GamepadColumn/GamepadText

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_text()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("show_controls"):
		visible = !visible
		get_viewport().set_input_as_handled()


func _update_text() -> void:
	keyboard_label.text = "W / A / S / D  - Move\nMouse  - Look\nSpace  - Jump\nLeft Click  - Harvest / Remove Block\nRight Click  - Place Block\n1-9 / 0  - Select Inventory Slot\nEsc  - Pause Menu\nF1  - Toggle Controls Help"
	gamepad_label.text = "Left Stick  - Move\nRight Stick  - Look\nA  - Jump / Menu Select\nLT  - Place Block\nRT  - Harvest / Remove Block\nLB / RB  - Cycle Inventory Slot\nStart  - Pause Menu\nD-Pad Up/Down  - Menu Navigate\nB  - Back / Close Menu\nF1 (Keyboard)  - Toggle Controls Help"
