extends Node3D

@export var width: int = 100
@export var depth: int = 100
@export var block_size: float = 0.5
@export var block_scene: PackedScene = preload("res://ground_block.tscn")
@export var terrain_amplitude: int = 8
@export var noise_seed: int = 42

@onready var blocks = $Blocks

var _height_map: Dictionary = {}
var _start_x: float = 0.0
var _start_z: float = 0.0
var _fill_blocks: Dictionary = {}    # Vector3i -> MeshInstance3D
var _surface_blocks: Dictionary = {} # Vector3i -> StaticBody3D

# Shared mesh/material for interior fill blocks (no physics, visual only)
var _fill_mesh: BoxMesh
var _fill_mat_grass: StandardMaterial3D
var _fill_mat_dirt: StandardMaterial3D


func _ready() -> void:
	_build_fill_resources()
	_generate_ground()
	_snap_trees_to_terrain()


func _build_fill_resources() -> void:
	_fill_mesh = BoxMesh.new()
	_fill_mesh.size = Vector3.ONE * block_size

	_fill_mat_grass = StandardMaterial3D.new()
	_fill_mat_grass.albedo_color = Color(0.36, 0.73, 0.30)
	_fill_mat_grass.roughness = 1.0

	_fill_mat_dirt = StandardMaterial3D.new()
	_fill_mat_dirt.albedo_color = Color(0.46, 0.30, 0.18)
	_fill_mat_dirt.roughness = 1.0


func get_height_at(world_x: float, world_z: float) -> float:
	var xi = int(round((world_x - _start_x) / block_size))
	var zi = int(round((world_z - _start_z) / block_size))
	var key = Vector2i(xi, zi)
	if _height_map.has(key):
		return _height_map[key] * block_size
	return 0.0


func _snap_trees_to_terrain() -> void:
	for child in get_parent().get_children():
		if child.name.begins_with("BirchTree"):
			child.global_position.y = get_height_at(child.global_position.x, child.global_position.z)


func on_surface_removed(grid_pos: Vector3i) -> void:
	_surface_blocks.erase(grid_pos)
	var below = Vector3i(grid_pos.x, grid_pos.y - 1, grid_pos.z)
	if not _fill_blocks.has(below):
		return
	# Promote the fill block below into a real collidable surface block
	var fill_node: MeshInstance3D = _fill_blocks[below]
	_fill_blocks.erase(below)
	fill_node.queue_free()
	var new_surface = block_scene.instantiate()
	new_surface.position = Vector3(
		_start_x + below.x * block_size,
		below.y * block_size,
		_start_z + below.z * block_size
	)
	new_surface.add_to_group("ground_block")
	new_surface.set_meta("grid_pos", below)
	_surface_blocks[below] = new_surface
	blocks.add_child(new_surface)


func _generate_ground() -> void:
	for child in blocks.get_children():
		child.queue_free()

	_height_map.clear()
	_fill_blocks.clear()
	_surface_blocks.clear()

	_start_x = -floor(width * 0.5) * block_size
	_start_z = -floor(depth * 0.5) * block_size

	# Large hills: low frequency, 70% weight
	var noise_large = FastNoiseLite.new()
	noise_large.seed = noise_seed
	noise_large.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_large.frequency = 0.04

	# Small bumps: higher frequency, 30% weight
	var noise_small = FastNoiseLite.new()
	noise_small.seed = noise_seed + 1
	noise_small.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_small.frequency = 0.15

	for xi in range(width):
		for zi in range(depth):
			var world_x = _start_x + xi * block_size
			var world_z = _start_z + zi * block_size

			var n = noise_large.get_noise_2d(world_x, world_z) * 0.7 \
				  + noise_small.get_noise_2d(world_x, world_z) * 0.3

			var height_blocks = int(round(n * terrain_amplitude))
			_height_map[Vector2i(xi, zi)] = height_blocks

			# Surface block: full StaticBody3D with collision — harvestable via raycast
			var surface = block_scene.instantiate()
			surface.position = Vector3(world_x, height_blocks * block_size, world_z)
			surface.add_to_group("ground_block")
			var surf_key = Vector3i(xi, height_blocks, zi)
			surface.set_meta("grid_pos", surf_key)
			_surface_blocks[surf_key] = surface
			blocks.add_child(surface)

			# Interior fill: visual-only MeshInstance3D, no physics body
			# Avoids ~90k StaticBody3D overwhelming Jolt physics init
			for yi in range(-terrain_amplitude, height_blocks):
				var fill = MeshInstance3D.new()
				fill.mesh = _fill_mesh
				# Top visible face uses grass colour, rest use dirt
				fill.material_override = _fill_mat_dirt
				fill.position = Vector3(world_x, yi * block_size, world_z)
				var fill_key = Vector3i(xi, yi, zi)
				_fill_blocks[fill_key] = fill
				blocks.add_child(fill)
