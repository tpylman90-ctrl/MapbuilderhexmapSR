extends Node3D

const GRID_COLUMNS: int = 64
const GRID_ROWS: int = 128
const HEX_RADIUS: float = 1.0
const HEX_HEIGHT: float = 0.22

func _ready() -> void:
	_configure_world()
	_build_grid()
	var camera := get_node_or_null("Camera3D") as Camera3D
	if camera != null:
		camera.look_at(Vector3.ZERO, Vector3.UP)

func _configure_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101813")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b6c6a2")
	environment.ambient_light_energy = 0.55
	world.environment = environment
	add_child(world)

func _build_grid() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(150.0, 250.0)
	var floor := MeshInstance3D.new()
	floor.name = "GridBacking"
	floor.mesh = floor_mesh
	floor.position.y = -0.16
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("18221b")
	floor_material.roughness = 1.0
	floor.material_override = floor_material
	add_child(floor)

	var hex_mesh := CylinderMesh.new()
	hex_mesh.top_radius = HEX_RADIUS * 0.94
	hex_mesh.bottom_radius = HEX_RADIUS * 0.94
	hex_mesh.height = HEX_HEIGHT
	hex_mesh.radial_segments = 6
	hex_mesh.rings = 1

	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = hex_mesh
	instances.instance_count = GRID_COLUMNS * GRID_ROWS
	var hex_basis := Basis(Vector3.UP, deg_to_rad(30.0))
	var index := 0
	for row in range(GRID_ROWS):
		var row_offset := 0.5 if row % 2 == 1 else 0.0
		for column in range(GRID_COLUMNS):
			var x := sqrt(3.0) * (column + row_offset - GRID_COLUMNS * 0.5)
			var z := 1.5 * (row - GRID_ROWS * 0.5)
			instances.set_instance_transform(index, Transform3D(hex_basis, Vector3(x, 0.0, z)))
			index += 1

	var grid := MultiMeshInstance3D.new()
	grid.name = "HexGrid64x128"
	grid.multimesh = instances
	var hex_material := StandardMaterial3D.new()
	hex_material.albedo_color = Color("7d9859")
	hex_material.roughness = 0.95
	grid.material_override = hex_material
	add_child(grid)
