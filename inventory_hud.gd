extends HBoxContainer

@onready var player: CharacterBody3D = get_parent().get_parent().get_node("Player")

const SLOT_COUNT = 10
const COLOR_WOOD = Color(0.93, 0.91, 0.85)
const COLOR_GROUND = Color(0.4, 0.7, 0.25)
const COLOR_EMPTY = Color(0.15, 0.15, 0.15)
const COLOR_SELECTED_BORDER = Color(0.0, 0.0, 0.0)
const COLOR_NORMAL_BORDER = Color(0.35, 0.35, 0.35)


func _ready() -> void:
	player.inventory_changed.connect(_refresh_slots)
	_refresh_slots()


func _refresh_slots() -> void:
	for i in SLOT_COUNT:
		var panel: Panel = get_child(i)
		if not panel:
			continue
		var icon: ColorRect = panel.get_node("Icon")
		var count_label: Label = panel.get_node("Count")

		var slot = player.inventory[i]

		# Update icon color
		if slot == null:
			icon.color = COLOR_EMPTY
		elif slot["type"] == "wood":
			icon.color = COLOR_WOOD
		else:
			icon.color = COLOR_GROUND

		# Update count label
		if slot != null and slot["count"] > 0:
			count_label.text = str(slot["count"])
			count_label.visible = true
		else:
			count_label.visible = false

		# Update border (selected slot gets black border)
		var style = StyleBoxFlat.new()
		style.draw_center = false
		var border_width: int
		if i == player.selected_slot:
			style.border_color = COLOR_SELECTED_BORDER
			border_width = 3
		else:
			style.border_color = COLOR_NORMAL_BORDER
			border_width = 1
		style.set_border_width_all(border_width)
		panel.add_theme_stylebox_override("panel", style)

		# Inset the Icon so the border is not covered by it
		icon.offset_left = border_width
		icon.offset_top = border_width
		icon.offset_right = -border_width
		icon.offset_bottom = -border_width
