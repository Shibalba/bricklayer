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
# Perf test control: enables per-stage generation logs.
var _perf_debug_enabled: bool = false
# Perf test control: spike threshold shared with generator logs.
var _perf_spike_threshold_ms: float = 12.0
var _generation_stage: int = 0
var _generation_complete: bool = false
var _heights: PackedInt32Array = PackedInt32Array()
var _chunk_start_us: int = 0
# Perf telemetry: accumulated noise stage time.
var _noise_us: int = 0
# Perf telemetry: accumulated surface block stage time.
var _surface_us: int = 0
# Perf telemetry: accumulated tree generation time.
var _tree_us: int = 0
# Perf telemetry: accumulated fill stage time.
var _fill_us: int = 0
# Perf telemetry: accumulated mesh rebuild stage time.
var _mesh_us: int = 0
var _tree_count: int = 0
# Perf telemetry: queue-enter timestamp for end-to-end chunk latency.
var _queue_enter_us: int = 0
# Perf test control: minimum stage time required to emit a stage log.
var _stage_log_threshold_ms: float = 2.0

enum GenerationStage {
	NOISE,
	SURFACE_TREES,
	FILL,
	MESH,
	READY
}

func generate(c_pos: Vector2i, b_size: float, t_amp: int, n_large: FastNoiseLite, n_small: FastNoiseLite, b_scene: PackedScene, f_mesh: BoxMesh, mat_dirt: StandardMaterial3D, perf_debug_enabled: bool = false, perf_spike_threshold_ms: float = 12.0, queue_enter_us: int = 0, stage_log_threshold_ms: float = 2.0) -> void:
	chunk_pos = c_pos
	block_size = b_size
	terrain_amplitude = t_amp
	noise_large = n_large
	noise_small = n_small
	block_scene = b_scene
	fill_mesh = f_mesh
	fill_mat_dirt = mat_dirt
	_perf_debug_enabled = perf_debug_enabled
	_perf_spike_threshold_ms = perf_spike_threshold_ms
	_queue_enter_us = queue_enter_us if queue_enter_us > 0 else Time.get_ticks_usec()
	_stage_log_threshold_ms = stage_log_threshold_ms
	
	_start_x = chunk_pos.x * CHUNK_SIZE * block_size
	_start_z = chunk_pos.y * CHUNK_SIZE * block_size
	_surface_blocks.clear()
	_fill_set.clear()
	_heights = PackedInt32Array()
	_chunk_start_us = Time.get_ticks_usec()
	_noise_us = 0
	_surface_us = 0
	_tree_us = 0
	_fill_us = 0
	_mesh_us = 0
	_tree_count = 0
	_generation_stage = GenerationStage.NOISE
	_generation_complete = false


func process_generation_step() -> bool:
	if _generation_complete:
		return true

	match _generation_stage:
		GenerationStage.NOISE:
			_stage_noise()
			_generation_stage = GenerationStage.SURFACE_TREES
		GenerationStage.SURFACE_TREES:
			_stage_surface_and_trees()
			_generation_stage = GenerationStage.FILL
		GenerationStage.FILL:
			_stage_fill()
			_generation_stage = GenerationStage.MESH
		GenerationStage.MESH:
			_stage_mesh()
			_generation_stage = GenerationStage.READY
			_generation_complete = true
		GenerationStage.READY:
			_generation_complete = true

	return _generation_complete


func is_generation_complete() -> bool:
	return _generation_complete


func get_compute_ms() -> float:
	var total_us: int = _noise_us + _surface_us + _tree_us + _fill_us + _mesh_us
	return total_us / 1000.0


func get_latency_ms() -> float:
	return (Time.get_ticks_usec() - _queue_enter_us) / 1000.0


func _stage_noise() -> void:
	var stage_start_us: int = Time.get_ticks_usec()
	_heights.resize(CHUNK_SIZE * CHUNK_SIZE)
	for xi in range(CHUNK_SIZE):
		for zi in range(CHUNK_SIZE):
			var world_x: float = _start_x + xi * block_size
			var world_z: float = _start_z + zi * block_size
			var n: float = noise_large.get_noise_2d(world_x, world_z) * 0.7 + noise_small.get_noise_2d(world_x, world_z) * 0.3
			_heights[_height_index(xi, zi)] = int(round(n * terrain_amplitude))
	_noise_us += Time.get_ticks_usec() - stage_start_us
	_log_stage_if_needed("noise", _noise_us)


func _stage_surface_and_trees() -> void:
	var stage_start_us: int = Time.get_ticks_usec()
	for xi in range(CHUNK_SIZE):
		for zi in range(CHUNK_SIZE):
			var world_x: float = _start_x + xi * block_size
			var world_z: float = _start_z + zi * block_size
			var height_blocks: int = _heights[_height_index(xi, zi)]

			var surface_start_us: int = Time.get_ticks_usec()
			var surface: Node3D = block_scene.instantiate() as Node3D
			if surface:
				surface.position = Vector3(world_x, height_blocks * block_size, world_z)
				surface.add_to_group("ground_block")
				var surf_key: Vector3i = Vector3i(chunk_pos.x * CHUNK_SIZE + xi, height_blocks, chunk_pos.y * CHUNK_SIZE + zi)
				surface.set_meta("grid_pos", surf_key)
				_surface_blocks[surf_key] = surface
				add_child(surface)
			_surface_us += Time.get_ticks_usec() - surface_start_us

			var r: int = abs(chunk_pos.x * 73 + chunk_pos.y * 127 + xi * 31 + zi * 17) % 266
			if r == 0:
				var tree_start_us: int = Time.get_ticks_usec()
				var tree: Node3D = tree_scene.instantiate() as Node3D
				if tree:
					tree.position = Vector3(world_x, height_blocks * block_size, world_z)
					add_child(tree)
					_tree_count += 1
				_tree_us += Time.get_ticks_usec() - tree_start_us
	_log_stage_if_needed("surface", _surface_us)
	_log_stage_if_needed("trees", _tree_us)


func _stage_fill() -> void:
	var stage_start_us: int = Time.get_ticks_usec()
	for xi in range(CHUNK_SIZE):
		for zi in range(CHUNK_SIZE):
			var world_x: float = _start_x + xi * block_size
			var world_z: float = _start_z + zi * block_size
			var height_blocks: int = _heights[_height_index(xi, zi)]
			for yi in range(-terrain_amplitude, height_blocks):
				var fill_key: Vector3i = Vector3i(chunk_pos.x * CHUNK_SIZE + xi, yi, chunk_pos.y * CHUNK_SIZE + zi)
				_fill_set[fill_key] = Vector3(world_x, yi * block_size, world_z)
	_fill_us += Time.get_ticks_usec() - stage_start_us
	_log_stage_if_needed("fill", _fill_us)


func _stage_mesh() -> void:
	var stage_start_us: int = Time.get_ticks_usec()
	_rebuild_fill_multimesh()
	_mesh_us += Time.get_ticks_usec() - stage_start_us
	_log_stage_if_needed("mesh", _mesh_us)


func _log_stage_if_needed(stage_name: String, stage_us: int) -> void:
	if not _perf_debug_enabled:
		return
	var stage_ms: float = stage_us / 1000.0
	if stage_ms >= _stage_log_threshold_ms:
		print("[ChunkPerf] chunk=%s stage=%s stage_ms=%.2f" % [str(chunk_pos), stage_name, stage_ms])


func _height_index(xi: int, zi: int) -> int:
	return xi * CHUNK_SIZE + zi

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
		
	var visible_positions: Array[Vector3] = []
	for key_variant in _fill_set.keys():
		var key: Vector3i = key_variant as Vector3i
		if not _fill_set.has(Vector3i(key.x - 1, key.y, key.z)) \
		or not _fill_set.has(Vector3i(key.x + 1, key.y, key.z)) \
		or not _fill_set.has(Vector3i(key.x, key.y - 1, key.z)) \
		or not _fill_set.has(Vector3i(key.x, key.y + 1, key.z)) \
		or not _fill_set.has(Vector3i(key.x, key.y, key.z - 1)) \
		or not _fill_set.has(Vector3i(key.x, key.y, key.z + 1)):
			var fill_pos: Vector3 = _fill_set[key] as Vector3
			visible_positions.append(fill_pos)
			
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = fill_mesh
	mm.instance_count = visible_positions.size()
	for i in visible_positions.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, visible_positions[i]))
	
	_fill_mmi.multimesh = mm
	_fill_mmi.material_override = fill_mat_dirt
