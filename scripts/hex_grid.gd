class_name HexGrid
extends RefCounted

const COLUMNS: int = 64
const ROWS: int = 128
const MAX_ELEVATION: int = 15
const MIN_ELEVATION: int = -15
const HEIGHT_PER_LEVEL: float = 0.75
const HEX_RADIUS: float = 1.0

enum Terrain { GRASS, DIRT, STONE, WATER }

const TERRAIN_COLORS: Array[Color] = [
	Color("7d9859"),
	Color("94704c"),
	Color("92918a"),
	Color("477e9d")
]
const TERRAIN_NAMES: Array[String] = ["Grass", "Dirt", "Stone", "Water"]
const EDGE_AXIAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0)
]

var elevations: PackedInt32Array
var terrain_ids: PackedByteArray

func _init() -> void:
	elevations.resize(COLUMNS * ROWS)
	elevations.fill(0)
	terrain_ids.resize(COLUMNS * ROWS)
	terrain_ids.fill(Terrain.GRASS)

func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < COLUMNS and cell.y >= 0 and cell.y < ROWS

func index_of(cell: Vector2i) -> int:
	return cell.y * COLUMNS + cell.x

func cell_from_index(index: int) -> Vector2i:
	return Vector2i(index % COLUMNS, floori(float(index) / COLUMNS))

func elevation_at(cell: Vector2i) -> int:
	return elevations[index_of(cell)] if contains(cell) else 0

func terrain_at(cell: Vector2i) -> int:
	return terrain_ids[index_of(cell)] if contains(cell) else Terrain.GRASS

func set_elevation(cell: Vector2i, level: int) -> void:
	if contains(cell):
		elevations[index_of(cell)] = clampi(level, MIN_ELEVATION, MAX_ELEVATION)

func set_terrain(cell: Vector2i, terrain: int) -> void:
	if contains(cell):
		terrain_ids[index_of(cell)] = clampi(terrain, Terrain.GRASS, Terrain.WATER)

func world_center(cell: Vector2i) -> Vector3:
	var row_offset := 0.5 if cell.y % 2 == 1 else 0.0
	var x := sqrt(3.0) * (cell.x + row_offset - (COLUMNS - 1) * 0.5 - 0.25)
	var z := 1.5 * (cell.y - (ROWS - 1) * 0.5)
	return Vector3(x, 0.0, z)

func axial_coordinates(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x - floori(float(cell.y) * 0.5), cell.y)

func neighbor_for_edge(cell: Vector2i, edge: int) -> Vector2i:
	var axial := axial_coordinates(cell) + EDGE_AXIAL_DIRECTIONS[edge]
	var column := axial.x + floori(float(axial.y) * 0.5)
	return Vector2i(column, axial.y)

func brush_cells(center: Vector2i, brush_size: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var radius := maxi(0, brush_size - 1)
	var center_axial := axial_coordinates(center)
	for row in range(maxi(0, center.y - radius), mini(ROWS, center.y + radius + 1)):
		for column in range(maxi(0, center.x - radius), mini(COLUMNS, center.x + radius + 1)):
			var cell := Vector2i(column, row)
			var axial := axial_coordinates(cell)
			var dq := axial.x - center_axial.x
			var dr := axial.y - center_axial.y
			var hex_distance := maxi(absi(dq), maxi(absi(dr), absi(dq + dr)))
			if hex_distance <= radius:
				result.append(cell)
	return result

func world_to_cell(world_x: float, world_z: float) -> Vector2i:
	var approximate_row := roundi(world_z / 1.5 + (ROWS - 1) * 0.5)
	var best_cell := Vector2i(-1, -1)
	var best_distance := INF
	for row in range(approximate_row - 1, approximate_row + 2):
		if row < 0 or row >= ROWS:
			continue
		var row_offset := 0.5 if row % 2 == 1 else 0.0
		var approximate_column := roundi(world_x / sqrt(3.0) + (COLUMNS - 1) * 0.5 + 0.25 - row_offset)
		for column in range(approximate_column - 1, approximate_column + 2):
			var cell := Vector2i(column, row)
			if not contains(cell):
				continue
			var center := world_center(cell)
			var local_x := absf(world_x - center.x)
			var local_z := absf(world_z - center.z)
			var inside_hex := local_x <= HEX_RADIUS * 0.8661 and local_z + local_x / sqrt(3.0) <= HEX_RADIUS
			var distance := Vector2(world_x - center.x, world_z - center.z).length_squared()
			if inside_hex and distance < best_distance:
				best_distance = distance
				best_cell = cell
	return best_cell
