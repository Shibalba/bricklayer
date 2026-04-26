extends Node3D
class_name TerrainChunk

var chunk_pos: Vector2i
var block_size: float
var terrain_amplitude: int
var noise_large: FastNoiseLite
var noise_small: FastNoiseLite
var block_scene: PackedScene
var fill_mesh: BoxMesh
var fill_mat_dirt: StandardMaterial3D

const CHUNK_SIZE = 16

var _surface_blocks: Dictionary = {}
var _fill_set: Dictionary = {}
var _fill_mmi: MultiMeshInstance3D
var _start_x: float
var _start_z: float
var tree_scene = preload("res://birch_tree.tscn")

func generate(c_pos: Vector2i, b_size: float, t_amp: int, n_large: FastNoiseLite, n_small: FastNoiseLite, b_scene: PackedScene, f_mesh: BoxMesh, mat_dirt: StandardMaterial3D) -> void:
	chunk_pos = c_pos
	block_size = b_size
	terrain_amplitude = t_amp
	noise_large = n_large
	noise_small = n_small
	block_scene = b_scene
	fill_mesh = f_mesh
	fill_mat_dirt = mat_dirt
	
	_start_x = chunk_pos.x * CHUNK_SIZE * block_size
	_start_z = chunk_pos.y * CHUNK_SIZE * block_size
	
	_generate_content()

func _generate_content() -> void:
	for xi in range(CHUNK_SIZE):
		for zi in range(CHUNK_SIZE):
			var world_x = _start_x + xi * block_size
			var world_z = _start_z + zi * block_size

			var n = noise_large.get_noise_2d(world_x, world_z) * 0.7 + noise_small.get_noise_2d(world_x, world_z) * 0.3

			var height_blocks = int(round(n * terrain_amplitude))

			var surface = block_scene.instantiate()
			surface.position = Vector3(world_x, height_blocks * block_size, world_z)
			surface.add_to_group("ground_block")
			var surf_key = Vector3i(chunk_pos.x * CHUNK_SIZE + xi, height_blocks, chunk_pos.y * CHUNK_SIZE + zi)
			surface.set_meta("grid_pos", surf_key)
			_surface_blocks[surf_key] = surface
			add_child(surface)

			var r = abs(chunk_pos.x * 73 + chunk_pos.y * 127 + xi * 31 + zi * 17) % 266
			if r == 0:
				var tree = tree_scene.instantiate()
				tree.position = Vector3(world_x, height_blocks * block_size, world_z)
				add_child(tree)

			for yi in range(-terrain_amplitude, height_blocks):
				var fill_key = Vector3i(chunk_pos.x * CHUNK_SIZE + xi, yi, chunk_pos.y * CHUNK_SIZE + zi)
				_fill_set[fill_key] = Vector3(world_x, yi * block_size, world_z)
	_rebuild_fill_multimesh()

func on_block_placed(snapped_pos: Vector3, placed_grid_pos: Vector3i, player_bricks_node: Node3D) -> void:
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
		var adj_pos = placed_grid_pos + offset
		if _surface_blocks.has(adj_pos):
			var completely_hidden = true
			
			for inner_offset in adjacent_offsets:
				var neighbor_pos = adj_pos + inner_offset
				var is_solid = false
				
				if _fill_set.has(neighbor_pos) or _surface_blocks.has(neighbor_pos) or neighbor_pos == placed_grid_pos:
					is_solid = true
				else:
					var world_pos = Vector3(neighbor_pos.x * block_size, neighbor_pos.y * block_size, neighbor_pos.z * block_size)
					for block in player_bricks_node.get_children():
						if block.position.distance_squared_to(world_pos) < 0.01:
							is_solid = true
							break
				
				if not is_solid:
					completely_hidden = false
					break
			
			if completely_hidden:
				var surface_block = _surface_blocks[adj_pos]
				var world_pos = surface_block.position
				_fill_set[adj_pos] = world_pos
				_surface_blocks.erase(adj_pos)
				surface_block.queue_free()
				multimesh_needs_rebuild = true
	
	if multimesh_needs_rebuild:
		_rebuild_fill_multimesh()

func on_block_removed(world_pos: Vector3, grid_pos: Vector3i) -> void:
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
			_fill_set.erase(adj_pos)
			multimesh_needs_rebuild = true
			
			var new_surface = block_scene.instantiate()
			new_surface.position = Vector3(
				adj_pos.x * block_size,
				adj_pos.y * block_size,
				adj_pos.z * block_size
			)
			new_surface.add_to_group("ground_block")
			new_surface.set_meta("grid_pos", adj_pos)
			_surface_blocks[adj_pos] = new_surface
			add_child(new_surface)
			
	if multimesh_needs_rebuild:
		_rebuild_fill_multimesh()

func _rebuild_fill_multimesh() -> void:
	if _fill_mmi == null:
		_fill_mmi = MultiMeshInstance3D.new()
		add_child(_fill_mmi)
		
	var visible_positions: Array = []
	for key in _fill_set:
		if not _fill_set.has(Vector3i(key.x - 1, key.y, key.z)) \
		or not _fill_set.has(Vector3i(key.x + 1, key.y, key.z)) \
		or not _fill_set.has(Vector3i(key.x, key.y, key.z - 1)) \
		or not _fill_set.has(Vector3i(key.x, key.y, key.z + 1)):
			visible_positions.append(_fill_set[key])
			
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = fill_mesh
	mm.instance_count = visible_positions.size()
	for i in visible_positions.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, visible_positions[i]))
	
	_fill_mmi.multimesh = mm
	_fill_mmi.material_override = fill_mat_dirt
