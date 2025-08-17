extends Node2D

signal map_updated

# --- Data Definitions ---
@export_group("Actor Definitions")
@export var player_stats: ActorStats
@export var alien_stats: ActorStats

# --- Game State Variables ---
@export_group("Map Generation")
@export var tile_size = 24
@export var level_transition = 2.0

@export_group("Tile Definitions")
@export var floor_tile: TileStats
@export var wall_tile: TileStats
@export var stairs_tile: TileStats
@export var health_tile: TileStats
@export var hp_up_tile: TileStats
@export var light_tile: TileStats
@export var acid_tile: TileStats
@export var corpse_tile: TileStats

@export_group("Armor: Peak Level")
@export var lo_peak_armor_level = 5
@export var hi_peak_armor_level = 9
var peak_armor_level = randi_range(lo_peak_armor_level, hi_peak_armor_level)
@export_group("Armor: Chance")
@export var min_armor_chance = 35
@export var max_armor_chance = 100
@export_group("Armor: Chance Falloff")
@export var lo_armor_chance_falloff = 5
@export var hi_armor_chance_falloff = 11
var armor_chance_falloff = randi_range(lo_armor_chance_falloff, hi_armor_chance_falloff)
@export_group("Armor: at Peak")
@export var min_armor_at_peak = 3
@export var max_armor_at_peak = 8
@export_group("Armor: Quantity Falloff")
@export var lo_armor_quantity_falloff = 1
@export var hi_armor_quantity_falloff = 2
var armor_quantity_falloff = randi_range(lo_armor_quantity_falloff, hi_armor_quantity_falloff)
@export_group("Armor: Min to Place (if passes)")
@export var min_armor_to_place = 1

var tile_data = {}
var fog_map = []
var tile_nodes = []
var map_data = []

var tile_font = preload("res://assets/fonts/SpaceMono-Regular.ttf")
var grabbable_items = []
var examinable_tiles = []


func _ready():
	_initialize_tile_data()
	map_data = generate_map()
	start_glow_effect()


func _initialize_tile_data():
	tile_data[GlobalEnums.TileType.FLOOR] = floor_tile
	tile_data[GlobalEnums.TileType.WALL] = wall_tile
	tile_data[GlobalEnums.TileType.STAIRS] = stairs_tile
	tile_data[GlobalEnums.TileType.HEALTH] = health_tile
	tile_data[GlobalEnums.TileType.HP_UP] = hp_up_tile
	tile_data[GlobalEnums.TileType.LIGHT] = light_tile
	tile_data[GlobalEnums.TileType.ACID] = acid_tile
	tile_data[GlobalEnums.TileType.CORPSE] = corpse_tile
	grabbable_items = [GlobalEnums.TileType.HP_UP]
	examinable_tiles = [GlobalEnums.TileType.HP_UP, GlobalEnums.TileType.CORPSE]


func generate_map():
	var width = 50
	var height = 50
	var new_map = []
	for y in range(height):
		var row = []
		for x in range(width):
			row.append(GlobalEnums.TileType.WALL)
		new_map.append(row)
	
	var digger_x = width / 2
	var digger_y = height / 2
	var steps_to_take = 2000
	for i in range(steps_to_take):
		new_map[digger_y][digger_x] = GlobalEnums.TileType.FLOOR
		var random_direction = randi_range(0, 3)
		if random_direction == 0: digger_y -= 1
		elif random_direction == 1: digger_y += 1
		elif random_direction == 2: digger_x -= 1
		elif random_direction == 3: digger_x += 1
		digger_x = clamp(digger_x, 1, width - 2)
		digger_y = clamp(digger_y, 1, height - 2)
	return new_map


func spawn_actors_and_items(actors):
	var player = actors[0]
	
	var player_placed = false
	while not player_placed:
		var px = randi_range(1, map_data[0].size() - 2)
		var py = randi_range(1, map_data.size() - 2)
		if map_data[py][px] == GlobalEnums.TileType.FLOOR:
			player["x"] = px
			player["y"] = py
			player_placed = true
	
	var enemies_to_place = 2 + GameState.level
	for i in range(enemies_to_place):
		var enemy_placed = false
		while not enemy_placed:
			var ex = randi_range(1, map_data[0].size() - 2)
			var ey = randi_range(1, map_data.size() - 2)
			if map_data[ey][ex] == GlobalEnums.TileType.FLOOR:
				actors.append({
					"x": ex, "y": ey, "hp": alien_stats.hp,
					"char": alien_stats.char, "color": alien_stats.color, "accuracy": alien_stats.accuracy
				})
				enemy_placed = true
	
	var stairs_placed = false
	while not stairs_placed:
		var sx = randi_range(1, map_data[0].size() - 2)
		var sy = randi_range(1, map_data.size() - 2)
		if map_data[sy][sx] == GlobalEnums.TileType.FLOOR and is_tile_open(sx, sy):
			map_data[sy][sx] = GlobalEnums.TileType.STAIRS
			stairs_placed = true
	
	# --- HP_UP & HEALTH Spawning ---
	var level_diff = abs(GameState.level - peak_armor_level)
	var armor_placed_this_level = 0
	
	var armor_spawn_chance = max_armor_chance - (level_diff * armor_chance_falloff)
	var final_armor_chance = clamp(armor_spawn_chance, min_armor_chance, max_armor_chance)
	
	if randi_range(1, 100) <= final_armor_chance:
		var current_max_armor = max_armor_at_peak - (level_diff * armor_quantity_falloff)
		var current_min_armor = min_armor_at_peak - (level_diff * armor_quantity_falloff)
		
		var final_max_armor = clamp(current_max_armor, min_armor_to_place, max_armor_at_peak)
		var final_min_armor = clamp(current_min_armor, min_armor_to_place, max_armor_at_peak)
		
		armor_placed_this_level = randi_range(final_min_armor, final_max_armor)
		
		for i in range(armor_placed_this_level):
			var hp_placed = false
			var placement_attempts = 0
			while not hp_placed and placement_attempts < 100:
				var px = randi_range(1, map_data[0].size() - 2)
				var py = randi_range(1, map_data.size() - 2)
				if map_data[py][px] == GlobalEnums.TileType.FLOOR:
					map_data[py][px] = GlobalEnums.TileType.HP_UP
					var item_position = Vector2(px, py)
					GameState.item_lore[item_position] = LoreManager.generate_scout_lore()
					hp_placed = true
				placement_attempts += 1
	
	var health_to_place = 1
	
	if armor_placed_this_level > 0:
		health_to_place += round(armor_placed_this_level * 0.75)
		
	health_to_place = clamp(health_to_place, 1, 4)
	
	for i in range(health_to_place):
		var health_placed = false
		var placement_attempts = 0
		while not health_placed and placement_attempts < 100:
			var px = randi_range(1, map_data[0].size() - 2)
			var py = randi_range(1, map_data.size() - 2)
			if map_data[py][px] == GlobalEnums.TileType.FLOOR and is_tile_open(px, py):
				map_data[py][px] = GlobalEnums.TileType.HEALTH
				health_placed = true
			placement_attempts += 1


	var light_chance = 100
	if GameState.level > 3:
		light_chance = max(35, 100 - ((GameState.level - 1) * 7))
	if randi_range(1, 100) <= light_chance:
		var light_placed = false
		while not light_placed:
			var px = randi_range(1, map_data[0].size() - 2)
			var py = randi_range(1, map_data.size() - 2)
			if map_data[py][px] == GlobalEnums.TileType.FLOOR:
				map_data[py][px] = GlobalEnums.TileType.LIGHT
				light_placed = true


	var acid_to_place = randi_range(10 + GameState.level * 10, 100 + GameState.level * 10)
	print(str(acid_to_place))
	var acid_attempts = 0
	var max_acid_attempts = acid_to_place * 20
	while acid_to_place > 0 and acid_attempts < max_acid_attempts:
		var ax = randi_range(1, map_data[0].size() - 2)
		var ay = randi_range(1, map_data.size() - 2)
		if map_data[ay][ax] == GlobalEnums.TileType.FLOOR:
			var pool_size = randi_range(4, 12)
			var placed_count = 0
			var queue = [Vector2i(ax, ay)]
			var visited = {Vector2i(ax, ay): true}
			while not queue.is_empty() and placed_count < pool_size and acid_to_place > 0:
				var current_pos = queue.pop_front()
				if map_data[current_pos.y][current_pos.x] == GlobalEnums.TileType.FLOOR:
					map_data[current_pos.y][current_pos.x] = GlobalEnums.TileType.ACID
					placed_count += 1
					acid_to_place -= 1
					var directions = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
					directions.shuffle()
					for dir in directions:
						var next_pos = current_pos + dir
						if not visited.has(next_pos):
							visited[next_pos] = true
							if next_pos.y > 0 and next_pos.y < map_data.size() - 1 and \
							next_pos.x > 0 and next_pos.x < map_data[0].size() - 1 and \
							map_data[next_pos.y][next_pos.x] == GlobalEnums.TileType.FLOOR:
								if randf() > 0.3:
									queue.append(next_pos)
		acid_attempts += 1


func create_map_tiles():
	fog_map.clear()
	tile_nodes.clear()
	for y in range(map_data.size()):
		var node_row = []
		var fog_row = []
		for x in range(map_data[y].size()):
			fog_row.append(GlobalEnums.FogState.HIDDEN)
			var tile_type = map_data[y][x]
			var new_tile = Label.new()
			new_tile.add_theme_font_override("font", tile_font)
			if tile_data.has(tile_type):
				var tile_def = tile_data[tile_type]
				new_tile.text = tile_def.char
			else:
				new_tile.text = tile_data[GlobalEnums.TileType.FLOOR].char
				
			if tile_type == GlobalEnums.TileType.LIGHT:
				new_tile.add_theme_color_override("font_shadow_color", Color(1, 1, 0, 0))
				new_tile.add_theme_constant_override("shadow_outline_size", 12)
				new_tile.add_theme_constant_override("shadow_offset_x", 0)
				new_tile.add_theme_constant_override("shadow_offset_y", 0)
			
			new_tile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			new_tile.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			new_tile.size = Vector2(tile_size, tile_size)
			new_tile.position = Vector2(x * tile_size, y * tile_size)
			add_child(new_tile)
			node_row.append(new_tile)
		tile_nodes.append(node_row)
		fog_map.append(fog_row)


func update_fog(player, actors):
	# --- PART 1: Update the fog_map data ---
	for y in range(fog_map.size()):
		for x in range(fog_map[y].size()):
			if fog_map[y][x] == GlobalEnums.FogState.VISIBLE:
				fog_map[y][x] = GlobalEnums.FogState.KNOWN
	
	var vision_radius = 2.5 # Default small radius for dark mode
	if GameState.has_light_source:
		vision_radius = 5 # Larger radius if we have a light
	
	var player_pos = Vector2(player["x"], player["y"])
	for y in range(player_pos.y - vision_radius, player_pos.y + vision_radius + 1):
		for x in range(player_pos.x - vision_radius, player_pos.x + vision_radius + 1):
			if y >= 0 and y < map_data.size() and x >= 0 and x < map_data[0].size():
				var tile_pos = Vector2(x, y)
				if player_pos.distance_to(tile_pos) < vision_radius:
					fog_map[y][x] = GlobalEnums.FogState.VISIBLE
	
	# --- PART 2: Update the visuals of map tiles ---
	for y in range(map_data.size()):
		for x in range(map_data[y].size()):
			var fog_state = fog_map[y][x]
			var tile_node = tile_nodes[y][x]
			var tile_type = map_data[y][x]
			var is_dark = not GameState.has_light_source or GameState.is_flickering
			
			if fog_state == GlobalEnums.FogState.VISIBLE:
				if tile_data.has(tile_type):
					var color = tile_data[tile_type].color
					if is_dark:
						if tile_type == GlobalEnums.TileType.LIGHT:
							tile_node.modulate = color
						else:
							var brightness = color.v / 2.5
							tile_node.modulate = Color(brightness, brightness, brightness)
					else:
						tile_node.modulate = color
			
			elif fog_state == GlobalEnums.FogState.KNOWN:
				if tile_type == GlobalEnums.TileType.LIGHT:
					tile_node.modulate = tile_data[tile_type].color * Color(0.5, 0.5, 0.5)
				else:
					tile_node.modulate = Color(0.2, 0.2, 0.2)
			
			else: # Hidden
				tile_node.modulate = Color(0, 0, 0)
	
	# --- PART 3: Update actor visuals ---
	for actor in actors:
		var fog_state = fog_map[actor["y"]][actor["x"]]
		var actor_pos = Vector2(actor["x"], actor["y"])
		var is_dark = not GameState.has_light_source or GameState.is_flickering
		
		if fog_state == GlobalEnums.FogState.VISIBLE:
			if is_dark and actor != player:
				if player_pos.distance_to(actor_pos) <= 1.5:
					actor["label"].visible = true
				else:
					actor["label"].visible = false
			else:
				actor["label"].visible = true
			
			actor["label"].text = actor["char"]
			actor["label"].modulate = actor["color"]
		else:
			actor["label"].visible = false


func is_tile_open(x, y):
	for j in range(y - 1, y + 2):
		for i in range (x - 1, x + 2):
			if j < 0 or j >= map_data.size() or i < 0 or i >= map_data[0].size():
				return false
			if map_data[j][i] == GlobalEnums.TileType.WALL:
				return false
	return true


func get_open_adjacent_tiles(x, y):
	var open_tiles = []
	var directions = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	directions.shuffle()
	
	for dir in directions:
		var adj_x = x + dir.x
		var adj_y = y + dir.y
		if map_data[adj_y][adj_x] != GlobalEnums.TileType.WALL:
			open_tiles.append(Vector2(adj_x, adj_y))
	return open_tiles


func start_glow_effect():
	for y in range(map_data.size()):
		for x in range(map_data[y].size()):
			if map_data[y][x] == GlobalEnums.TileType.LIGHT:
				var crystal_label = tile_nodes[y][x]
				var tween = create_tween()
				tween.set_loops()
				tween.tween_property(crystal_label, "theme_override_colors/font_shadow_color", Color(1, 1, 0, 0.3), 1.5).set_trans(Tween.TRANS_SINE)
				tween.tween_property(crystal_label, "theme_override_colors/font_shadow_color", Color(1, 1, 0, 0), 1.5).set_trans(Tween.TRANS_SINE)
