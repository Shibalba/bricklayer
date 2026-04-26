extends Node3D

@export var block_size: float = 0.5
@export var block_scene: PackedScene = preload("res://ground_block.tscn")
@export var terrain_amplitude: int = 8
@export var noise_seed: int = 42
@export var render_distance: int = 2

@onready var blocks = $Blocks
var chunk_scene = preload("res://terrain_chunk.gd")

var _chunks: Dictionary = {}
var _fill_mesh: BoxMesh
var _fill_mat_dirt: StandardMaterial3D
var noise_large: FastNoiseLite
var noise_small: FastNoiseLite
var _player: Node3D

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
	var player_chunk = _get_chunk_pos_from_world(_player.global_position)
	
	var active_chunks = []
	for x in range(-render_distance, render_distance + 1):
		for z in range(-render_distance, render_distance + 1):
			var c_pos = player_chunk + Vector2i(x, z)
			active_chunks.append(c_pos)
			if not _chunks.has(c_pos):
				_load_chunk(c_pos)
				
	var chunks_to_remove = []
	for c_pos in _chunks.keys():
		if not c_pos in active_chunks:
			chunks_to_remove.append(c_pos)
			
	for c_pos in chunks_to_remove:
		_chunks[c_pos].queue_free()
		_chunks.erase(c_pos)

func _get_chunk_pos_from_world(world_pos: Vector3) -> Vector2i:
	var grid_pos = _get_grid_pos_from_world(world_pos)
	return Vector2i(floor(float(grid_pos.x) / 16.0), floor(float(grid_pos.z) / 16.0))

func _load_chunk(c_pos: Vector2i) -> void:
	var chunk = Node3D.new()
	chunk.set_script(chunk_scene)
	blocks.add_child(chunk)
	chunk.generate(c_pos, block_size, terrain_amplitude, noise_large, noise_small, block_scene, _fill_mesh, _fill_mat_dirt)
	_chunks[c_pos] = chunk

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
	var grid_pos = _get_grid_pos_from_world(snapped_pos)
	var c_pos = _get_chunk_pos_from_world(snapped_pos)
	if _chunks.has(c_pos):
		_chunks[c_pos].on_block_placed(snapped_pos, grid_pos, player_bricks_node)

func on_block_removed(world_pos: Vector3) -> void:
	var grid_pos = _get_grid_pos_from_world(world_pos)
	var c_pos = _get_chunk_pos_from_world(world_pos)
	if _chunks.has(c_pos):
		_chunks[c_pos].on_block_removed(world_pos, grid_pos)
