extends Node3D

@export var block_size: float = 0.5
@export var block_scene: PackedScene = preload("res://ground_block.tscn")
@export var terrain_amplitude: int = 8
@export var noise_seed: int = 42
@export var render_distance: int = 2
@export var chunk_load_budget_ms: float = 6.0
@export var max_chunks_loaded_per_frame: int = 2
@export var max_chunks_unloaded_per_frame: int = 3
@export var perf_debug_enabled: bool = true
@export var perf_spike_threshold_ms: float = 12.0
@export var perf_frame_budget_target_ms: float = 16.6
@export var perf_log_queue_age_stats: bool = true
@export var perf_stage_log_threshold_ms: float = 2.0

@onready var blocks = $Blocks
var chunk_scene = preload("res://terrain_chunk.gd")

var _chunks: Dictionary = {}
var _fill_mesh: BoxMesh
var _fill_mat_dirt: StandardMaterial3D
var noise_large: FastNoiseLite
var noise_small: FastNoiseLite
var _player: Node3D
var _loading_chunks: Dictionary = {}
var _load_queue: Array[Vector2i] = []
var _queued_lookup: Dictionary = {}
var _queue_enter_us: Dictionary = {}
var _queue_sort_origin: Vector2i = Vector2i.ZERO
var _last_queue_age_log_us: int = 0

func _ready() -> void:
	if has_node("../Player"):
		_player = get_node("../Player")
	_build_fill_resources()
	
	noise_large = FastNoiseLite.new()
	noise_large.seed = noise_seed
	noise_large.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_large.frequency = 0.04

	noise_small = FastNoiseLite.new()
	noise_small.seed = noise_seed + 1
	noise_small.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise_small.frequency = 0.15

func _process(delta: float) -> void:
	if not _player:
		return
	_update_chunks()

func _update_chunks() -> void:
	var frame_start_us := Time.get_ticks_usec()
	var player_chunk: Vector2i = _get_chunk_pos_from_world(_player.global_position)
	
	var active_chunks_lookup: Dictionary = {}
	var missing_chunks: Array[Vector2i] = []
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var c_pos: Vector2i = player_chunk + Vector2i(x, z)
			active_chunks_lookup[c_pos] = true
			if not _chunks.has(c_pos) and not _queued_lookup.has(c_pos) and not _loading_chunks.has(c_pos):
				missing_chunks.append(c_pos)

	_queue_sort_origin = player_chunk
	missing_chunks.sort_custom(Callable(self, "_compare_chunk_distance"))
	for c_pos: Vector2i in missing_chunks:
		_queue_chunk_load(c_pos)

	_prune_load_queue(active_chunks_lookup)
	var queue_stats: Dictionary = _process_load_queue()
	var loaded_count: int = queue_stats["loaded"] as int
	var processed_steps: int = queue_stats["processed_steps"] as int
	var requeued_count: int = queue_stats["requeued"] as int
	var budget_hit: bool = queue_stats["budget_hit"] as bool
				
	var chunks_to_remove: Array[Vector2i] = []
	for c_pos_variant in _chunks.keys():
		var c_pos: Vector2i = c_pos_variant as Vector2i
		if not active_chunks_lookup.has(c_pos):
			chunks_to_remove.append(c_pos)

	var unload_count: int = min(max_chunks_unloaded_per_frame, chunks_to_remove.size())
	for i in range(unload_count):
		var c_pos: Vector2i = chunks_to_remove[i]
		_chunks[c_pos].queue_free()
		_chunks.erase(c_pos)

	var loading_to_remove: Array[Vector2i] = []
	for c_pos_variant in _loading_chunks.keys():
		var c_pos: Vector2i = c_pos_variant as Vector2i
		if not active_chunks_lookup.has(c_pos):
			loading_to_remove.append(c_pos)

	for c_pos in loading_to_remove:
		var loading_chunk: TerrainChunk = _loading_chunks[c_pos] as TerrainChunk
		if loading_chunk:
			loading_chunk.queue_free()
		_loading_chunks.erase(c_pos)
		_queue_enter_us.erase(c_pos)

	_log_queue_age_stats_if_needed()

	if perf_debug_enabled:
		var elapsed_ms: float = (Time.get_ticks_usec() - frame_start_us) / 1000.0
		var frame_over_budget: bool = elapsed_ms > perf_frame_budget_target_ms
		if loaded_count > 0 or unload_count > 0 or loading_to_remove.size() > 0 or budget_hit or frame_over_budget or elapsed_ms >= perf_spike_threshold_ms:
			print("[ChunkPerf] frame=%.2fms loaded=%d processed_steps=%d requeued=%d budget_hit=%s frame_over_budget=%s unloaded=%d loading_unloaded=%d queued=%d loading=%d" % [elapsed_ms, loaded_count, processed_steps, requeued_count, str(budget_hit), str(frame_over_budget), unload_count, loading_to_remove.size(), _load_queue.size(), _loading_chunks.size()])


func _compare_chunk_distance(a: Vector2i, b: Vector2i) -> bool:
	return a.distance_squared_to(_queue_sort_origin) < b.distance_squared_to(_queue_sort_origin)


func _queue_chunk_load(c_pos: Vector2i) -> void:
	if _chunks.has(c_pos) or _queued_lookup.has(c_pos) or _loading_chunks.has(c_pos):
		return
	if not _queue_enter_us.has(c_pos):
		_queue_enter_us[c_pos] = Time.get_ticks_usec()
	_load_queue.append(c_pos)
	_queued_lookup[c_pos] = true


func _prune_load_queue(active_chunks_lookup: Dictionary) -> void:
	if _load_queue.is_empty():
		return

	var kept: Array[Vector2i] = []
	for c_pos: Vector2i in _load_queue:
		if active_chunks_lookup.has(c_pos):
			kept.append(c_pos)
		else:
			_queued_lookup.erase(c_pos)
			_queue_enter_us.erase(c_pos)
	_load_queue = kept


func _process_load_queue() -> Dictionary:
	if max_chunks_loaded_per_frame <= 0:
		return {
			"loaded": 0,
			"processed_steps": 0,
			"requeued": 0,
			"budget_hit": false
		}

	var loaded_count: int = 0
	var processed_steps: int = 0
	var requeued_count: int = 0
	var budget_hit: bool = false
	var budget_start_us: int = Time.get_ticks_usec()

	while not _load_queue.is_empty() and processed_steps < max_chunks_loaded_per_frame:
		var elapsed_ms: float = (Time.get_ticks_usec() - budget_start_us) / 1000.0
		if elapsed_ms >= chunk_load_budget_ms:
			budget_hit = true
			break

		var c_pos: Vector2i = _load_queue.pop_front() as Vector2i
		_queued_lookup.erase(c_pos)
		if _chunks.has(c_pos):
			continue

		var chunk: TerrainChunk = _get_or_create_loading_chunk(c_pos)
		if not chunk:
			continue

		var chunk_start_us := Time.get_ticks_usec()
		var complete: bool = chunk.process_generation_step()
		processed_steps += 1

		if complete:
			var compute_ms: float = chunk.get_compute_ms()
			var latency_ms: float = chunk.get_latency_ms()
			_loading_chunks.erase(c_pos)
			_chunks[c_pos] = chunk
			_queue_enter_us.erase(c_pos)
			loaded_count += 1
			if perf_debug_enabled and (compute_ms >= perf_spike_threshold_ms or latency_ms >= perf_spike_threshold_ms):
				print("[ChunkPerf] chunk=%s compute=%.2fms latency=%.2fms" % [str(c_pos), compute_ms, latency_ms])
		else:
			_load_queue.append(c_pos)
			_queued_lookup[c_pos] = true
			requeued_count += 1

		if perf_debug_enabled:
			var chunk_elapsed_ms: float = (Time.get_ticks_usec() - chunk_start_us) / 1000.0
			if chunk_elapsed_ms >= perf_spike_threshold_ms:
				print("[ChunkPerf] chunk=%s step=%.2fms complete=%s" % [str(c_pos), chunk_elapsed_ms, str(complete)])

	return {
		"loaded": loaded_count,
		"processed_steps": processed_steps,
		"requeued": requeued_count,
		"budget_hit": budget_hit
	}

func _get_chunk_pos_from_world(world_pos: Vector3) -> Vector2i:
	var grid_pos: Vector3i = _get_grid_pos_from_world(world_pos)
	return Vector2i(floor(float(grid_pos.x) / 16.0), floor(float(grid_pos.z) / 16.0))

func _get_or_create_loading_chunk(c_pos: Vector2i) -> TerrainChunk:
	if _loading_chunks.has(c_pos):
		return _loading_chunks[c_pos] as TerrainChunk

	var chunk := TerrainChunk.new()
	blocks.add_child(chunk)
	var queue_enter_us: int = _queue_enter_us[c_pos] as int if _queue_enter_us.has(c_pos) else Time.get_ticks_usec()
	chunk.generate(c_pos, block_size, terrain_amplitude, noise_large, noise_small, block_scene, _fill_mesh, _fill_mat_dirt, perf_debug_enabled, perf_spike_threshold_ms, queue_enter_us, perf_stage_log_threshold_ms)
	_loading_chunks[c_pos] = chunk
	return chunk


func _log_queue_age_stats_if_needed() -> void:
	if not perf_debug_enabled or not perf_log_queue_age_stats:
		return

	var now_us: int = Time.get_ticks_usec()
	if now_us - _last_queue_age_log_us < 1_000_000:
		return
	_last_queue_age_log_us = now_us

	if _load_queue.is_empty():
		return

	var min_age_ms: float = 999999.0
	var max_age_ms: float = 0.0
	var total_age_ms: float = 0.0
	var count: int = 0
	for c_pos in _load_queue:
		if not _queue_enter_us.has(c_pos):
			continue
		var enter_us: int = _queue_enter_us[c_pos] as int
		var age_ms: float = (now_us - enter_us) / 1000.0
		min_age_ms = min(min_age_ms, age_ms)
		max_age_ms = max(max_age_ms, age_ms)
		total_age_ms += age_ms
		count += 1

	if count > 0:
		var avg_age_ms: float = total_age_ms / float(count)
		print("[ChunkPerf] queue_age queued=%d min=%.2fms avg=%.2fms max=%.2fms" % [count, min_age_ms, avg_age_ms, max_age_ms])

func _build_fill_resources() -> void:
	_fill_mesh = BoxMesh.new()
	_fill_mesh.size = Vector3.ONE * block_size

	_fill_mat_dirt = StandardMaterial3D.new()
	_fill_mat_dirt.albedo_color = Color(0.46, 0.30, 0.18)
	_fill_mat_dirt.roughness = 1.0

func _get_grid_pos_from_world(world_pos: Vector3) -> Vector3i:
	return Vector3i(
		int(round(world_pos.x / block_size)),
		int(round(world_pos.y / block_size)),
		int(round(world_pos.z / block_size))
	)

func on_block_placed(snapped_pos: Vector3, player_bricks_node: Node3D) -> void:
	var grid_pos: Vector3i = _get_grid_pos_from_world(snapped_pos)
	var c_pos: Vector2i = _get_chunk_pos_from_world(snapped_pos)
	if _chunks.has(c_pos):
		_chunks[c_pos].on_block_placed(snapped_pos, grid_pos, player_bricks_node)

func on_block_removed(world_pos: Vector3) -> void:
	var grid_pos: Vector3i = _get_grid_pos_from_world(world_pos)
	var c_pos: Vector2i = _get_chunk_pos_from_world(world_pos)
	if _chunks.has(c_pos):
		_chunks[c_pos].on_block_removed(world_pos, grid_pos)
