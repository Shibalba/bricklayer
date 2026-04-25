extends HBoxContainer

@onready var player: CharacterBody3D = get_parent().get_parent().get_node("Player")

const SLOT_COUNT = 10
const COLOR_WOOD = Color(0.72, 0.52, 0.30)
const COLOR_GROUND = Color(0.42, 0.28, 0.12)
const COLOR_EMPTY = Color(0.15, 0.15, 0.15)
const COLOR_SELECTED_BORDER = Color(0.0, 0.0, 0.0)
const COLOR_NORMAL_BORDER = Color(0.35, 0.35, 0.35)

var _style_selected: StyleBoxFlat
var _style_normal: StyleBoxFlat


func _ready() -> void:
	_style_selected = StyleBoxFlat.new()
	_style_selected.draw_center = false
	_style_selected.border_color = COLOR_SELECTED_BORDER
	_style_selected.set_border_width_all(3)

	_style_normal = StyleBoxFlat.new()
	_style_normal.draw_center = false
	_style_normal.border_color = COLOR_NORMAL_BORDER
	_style_normal.set_border_width_all(1)

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

		# Update border using pre-allocated styles (no allocation per frame)
		if i == player.selected_slot:
			panel.add_theme_stylebox_override("panel", _style_selected)
			icon.offset_left = 3
			icon.offset_top = 3
			icon.offset_right = -3
			icon.offset_bottom = -3
		else:
			panel.add_theme_stylebox_override("panel", _style_normal)
			icon.offset_left = 1
			icon.offset_top = 1
			icon.offset_right = -1
			icon.offset_bottom = -1
