extends Node3D

@export var trunk_height: int = 6
@export var leaf_radius: int = 2
@export var leaf_layers: int = 3
@export var block_size: float = 0.5
@export var trunk_base_y: float = 0.5

@onready var blocks = $Blocks

var trunk_mat: StandardMaterial3D
var bark_mark_mat: StandardMaterial3D
var leaf_mat: StandardMaterial3D
var voxel_mesh: BoxMesh
var voxel_shape: BoxShape3D


func _ready() -> void:
	_build_resources()
	_build_tree()


func _build_resources() -> void:
	trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.93, 0.91, 0.85)
	trunk_mat.roughness = 1.0

	bark_mark_mat = StandardMaterial3D.new()
	bark_mark_mat.albedo_color = Color(0.16, 0.16, 0.16)
	bark_mark_mat.roughness = 1.0

	leaf_mat = StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.43, 0.76, 0.29)
	leaf_mat.roughness = 1.0

	voxel_mesh = BoxMesh.new()
	voxel_mesh.size = Vector3.ONE * block_size

	voxel_shape = BoxShape3D.new()
	voxel_shape.size = Vector3.ONE * block_size


func _build_tree() -> void:
	for child in blocks.get_children():
		child.queue_free()

	_build_trunk()
	_build_leaves()


func _build_trunk() -> void:
	for y in range(trunk_height):
		var mat = trunk_mat
		# Sparse dark bands help sell the birch look without textures.
		if y == 1 or y == 3 or y == trunk_height - 2:
			mat = bark_mark_mat
		var body = _add_voxel(Vector3(0, y, 0), mat)
		body.add_to_group("wood")


func _build_leaves() -> void:
	var top_y = trunk_height

	for layer in range(leaf_layers):
		var y = top_y + layer
		var radius = max(1, leaf_radius - int(layer / 2.0))

		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				if abs(x) == radius and abs(z) == radius:
					continue
				if layer == 0 and x == 0 and z == 0:
					continue
				_add_voxel(Vector3(x, y, z), leaf_mat)

	_add_voxel(Vector3(0, top_y + leaf_layers, 0), leaf_mat)


func _add_voxel(grid_pos: Vector3, material: StandardMaterial3D) -> StaticBody3D:
	var body = StaticBody3D.new()
	body.position = Vector3(
		grid_pos.x * block_size,
		trunk_base_y + grid_pos.y * block_size,
		grid_pos.z * block_size
	)

	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = voxel_mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collider = CollisionShape3D.new()
	collider.shape = voxel_shape
	body.add_child(collider)

	blocks.add_child(body)
	return body
