extends Node3D

@export var width: int = 100
@export var depth: int = 100
@export var block_size: float = 0.5
@export var block_scene: PackedScene = preload("res://ground_block.tscn")
@export var terrain_amplitude: int = 8
@export var noise_seed: int = 42

@onready var blocks = $Blocks

var _height_array: PackedInt32Array
var _fill_set: Dictionary = {}       # Vector3i -> Vector3 (world position)
var _surface_blocks: Dictionary = {} # Vector3i -> StaticBody3D
var _fill_mmi: MultiMeshInstance3D
var _start_x: float = 0.0
var _start_z: float = 0.0
var _tree_nodes: Array = []

# Shared mesh/material for interior fill blocks (rendered as one MultiMesh draw call)
var _fill_mesh: BoxMesh
var _fill_mat_grass: StandardMaterial3D
var _fill_mat_dirt: StandardMaterial3D


func _ready() -> void:
	for child in get_parent().get_children():
		if child.name.begins_with("BirchTree"):
			_tree_nodes.append(child)
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
	if xi < 0 or xi >= width or zi < 0 or zi >= depth:
		return 0.0
	return _height_array[zi * width + xi] * block_size


func _snap_trees_to_terrain() -> void:
	for tree in _tree_nodes:
		tree.global_position.y = get_height_at(tree.global_position.x, tree.global_position.z)


func on_surface_removed(grid_pos: Vector3i) -> void:
	_surface_blocks.erase(grid_pos)
	
	var adjacent_offsets = [
		Vector3i(0, -1, 0),
		Vector3i(0, 1, 0),
		Vector3i(-1, 0, 0),
		Vector3i(1, 0, 0),
		Vector3i(0, 0, -1),
		Vector3i(0, 0, 1)
	]
	
	var multimesh_needs_rebuild = false
	
	for offset in adjacent_offsets:
		var adj_pos = grid_pos + offset
		if _fill_set.has(adj_pos):
			# Promote the adjacent fill voxel into a real collidable surface block
			_fill_set.erase(adj_pos)
			multimesh_needs_rebuild = true
			
			var new_surface = block_scene.instantiate()
			new_surface.position = Vector3(
				_start_x + adj_pos.x * block_size,
				adj_pos.y * block_size,
				_start_z + adj_pos.z * block_size
			)
			new_surface.add_to_group("ground_block")
			new_surface.set_meta("grid_pos", adj_pos)
			_surface_blocks[adj_pos] = new_surface
			blocks.add_child(new_surface)
			
	if multimesh_needs_rebuild:
		_rebuild_fill_multimesh()


func _rebuild_fill_multimesh() -> void:
	if _fill_mmi == null:
		_fill_mmi = MultiMeshInstance3D.new()
		blocks.add_child(_fill_mmi)
	# Only render fills with at least one exposed horizontal face.
	# A fill at (xi, yi, zi) is occluded on a side if _fill_set contains that neighbor.
	# Out-of-bounds neighbors are never in _fill_set, so edge fills are always exposed.
	var visible_positions: Array = []
	for key in _fill_set:
		if not _fill_set.has(Vector3i(key.x - 1, key.y, key.z)) \
		or not _fill_set.has(Vector3i(key.x + 1, key.y, key.z)) \
		or not _fill_set.has(Vector3i(key.x, key.y, key.z - 1)) \
		or not _fill_set.has(Vector3i(key.x, key.y, key.z + 1)):
			visible_positions.append(_fill_set[key])
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _fill_mesh
	mm.instance_count = visible_positions.size()
	for i in visible_positions.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, visible_positions[i]))
	_fill_mmi.multimesh = mm
	_fill_mmi.material_override = _fill_mat_dirt


func _generate_ground() -> void:
	for child in blocks.get_children():
		child.queue_free()

	_height_array.resize(width * depth)
	_fill_set.clear()
	_surface_blocks.clear()
	_fill_mmi = null  # queue_freed above with blocks.get_children()

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
			_height_array[zi * width + xi] = height_blocks

			# Surface block: full StaticBody3D with collision — harvestable via raycast
			var surface = block_scene.instantiate()
			surface.position = Vector3(world_x, height_blocks * block_size, world_z)
			surface.add_to_group("ground_block")
			var surf_key = Vector3i(xi, height_blocks, zi)
			surface.set_meta("grid_pos", surf_key)
			_surface_blocks[surf_key] = surface
			blocks.add_child(surface)

			# Interior fill: tracked by position, rendered as one MultiMesh draw call
			for yi in range(-terrain_amplitude, height_blocks):
				var fill_key = Vector3i(xi, yi, zi)
				_fill_set[fill_key] = Vector3(world_x, yi * block_size, world_z)

	_rebuild_fill_multimesh()
