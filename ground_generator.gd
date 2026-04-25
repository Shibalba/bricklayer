extends Node3D

@export var width: int = 100
@export var depth: int = 100
@export var block_size: float = 0.5
@export var block_scene: PackedScene = preload("res://ground_block.tscn")

@onready var blocks = $Blocks


func _ready() -> void:
	_generate_ground()


func _generate_ground() -> void:
	for child in blocks.get_children():
		child.queue_free()

	# Anchor generation to exact block-size multiples so it matches build snapping.
	var start_x = -floor(width * 0.5) * block_size
	var start_z = -floor(depth * 0.5) * block_size

	for x in range(width):
		for z in range(depth):
			var block = block_scene.instantiate()
			block.position = Vector3(
				start_x + x * block_size,
				0.0,
				start_z + z * block_size
			)
			blocks.add_child(block)
