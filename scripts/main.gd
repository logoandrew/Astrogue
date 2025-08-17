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

@export_group("Misc.")
@export var acid_damage_unit = 0.334
var acid_damage = 0.0

@onready var hud = $HUD


var tile_data = {}
var actors = []
var player
var fog_map = []
var tile_nodes = []
var map_data = []

var is_player_turn = true
var tile_font = preload("res://assets/fonts/SpaceMono-Regular.ttf")
var transitioning = false
var game_is_paused = false
var game_over = false
var grabbable_items = []
var examinable_tiles = []

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


# --- Godot Functions ---
func _ready():
	_initialize_tile_data()
	fade_from_black()
	
	# 1. Generate the map data
	map_data = generate_map()

	# 2. Spawn all actors (player and enemies) and items
	spawn_actors_and_items()
	
	# 3. Create the visual tiles for the map
	create_map_tiles()

	# 4. Create the visual labels for ALL actors
	create_actor_labels()

	# 5. Center the camera on the player
	var player_pixel_pos = player["label"].position
	var screen_center = get_viewport_rect().size / 2
	self.position = screen_center - player_pixel_pos

	# 6. Set the initial fog of war and UI
	start_glow_effect()
	update_fog()
	map_updated.emit()
	hud.quit_to_menu_requested.connect(_on_quit_to_menu_requested)
	hud.high_score_submitted.connect(_on_high_score_submitted)


func _process(delta):
	if get_tree().paused and Input.is_action_just_pressed("restart"):
		# Reset game state for a new run
		GameState.reset()
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	
	if Input.is_action_just_pressed("ui_cancel"):
		game_is_paused = not game_is_paused
		hud.get_node("QuitDialogue").visible = game_is_paused
	
	if not game_over and not transitioning:
		if is_player_turn:
			if Input.is_action_just_pressed("ui_right"):
				try_move(1, 0)
				is_player_turn = false
			elif Input.is_action_just_pressed("ui_left"):
				try_move(-1, 0)
				is_player_turn = false
			elif Input.is_action_just_pressed("ui_up"):
				try_move(0, -1)
				is_player_turn = false
			elif Input.is_action_just_pressed("ui_down"):
				try_move(0, 1)
				is_player_turn = false
			elif Input.is_action_just_pressed("examine"):
				examine_tile()
			elif Input.is_action_just_pressed("grab"):
				if pickup_item():
					is_player_turn = false
			
		if not is_player_turn:
			# Loop backwards when processing turns to avoid issues when an actor is removed
			for i in range(actors.size() - 1, 0, -1):
				var actor = actors[i]
				if actor["hp"] > 0:
					enemy_take_turn(actor)
					
			is_player_turn = true


func _draw():
	var grid_range = 50
	for i in range(-grid_range, grid_range + 1):
		var x = i * tile_size
		draw_line(Vector2(x, -grid_range * tile_size), Vector2(x, grid_range * tile_size), Color(0.1, 0.1, 0.1))

	for i in range(-grid_range, grid_range + 1):
		var y = i * tile_size
		draw_line(Vector2(-grid_range * tile_size, y), Vector2(grid_range * tile_size, y), Color(0.1, 0.1, 0.1))


func is_tile_open(x, y):
	for j in range(y - 1, y + 2):
		for i in range (x - 1, x + 2):
			if j < 0 or j >= map_data.size() or i < 0 or i >= map_data[0].size():
				return false
			if map_data[j][i] == GlobalEnums.TileType.WALL:
				return false
	return true


func get_actor_at(x, y):
	for actor in actors:
		if actor["x"] == x and actor["y"] == y:
			return actor
	return null


func try_move(dx, dy):
	var target_x = player["x"] + dx
	var target_y = player["y"] + dy
	
	var target_actor = get_actor_at(target_x, target_y)
	var target_tile_type = map_data[target_y][target_x]
	
	# Combat
	if target_actor != null and target_actor != player:
		shake_camera()
		var hit_chance = randi_range(1, 100)
		if hit_chance <= player["accuracy"]:
			target_actor.hp -= 1
			target_actor.health_bar.value = target_actor.hp
			hud.log_message("You hit the alien! It has " + str(target_actor.hp) + " HP left.", Color.ORANGE)
			if target_actor.hp <= 0:
				kill_actor(target_actor)
		else:
			hud.log_message("You swing at the alien and miss!", Color.GRAY)
	# Non-combat
	elif target_tile_type != GlobalEnums.TileType.WALL:
		var tile_def = tile_data.get(target_tile_type)
		var moved = true
		if tile_def and tile_def.pickup_method == "auto":
			if apply_item_effect(tile_def):
				map_data[target_y][target_x] = GlobalEnums.TileType.FLOOR
				tile_nodes[target_y][target_x].text = tile_data[GlobalEnums.TileType.FLOOR].char
				map_updated.emit()
			else:
				moved = false
				return
		if moved:
			player["x"] = target_x
			player["y"] = target_y
			player["label"].position = Vector2(player["x"] * tile_size, player["y"] * tile_size)
			self.position = Vector2( -player["x"] * tile_size, -player["y"] * tile_size) + get_viewport_rect().size / 2
			
			var current_tile_type = map_data[player.y][player.x]
			var available_actions = []
			if current_tile_type in examinable_tiles:
				available_actions.append("Press [e] to examine")
			if current_tile_type in grabbable_items:
				available_actions.append("Press [g] to pickup")
			if not available_actions.is_empty():
				hud.get_node("ActionsLabel").text = "  |  ".join(available_actions)
				hud.get_node("ActionsLabel").show()
			else: 
				hud.get_node("ActionsLabel").hide()
		
		if target_tile_type == GlobalEnums.TileType.STAIRS:
			if GameState.light_durability > 0 and GameState.light_durability < 10:
				GameState.light_durability += 10
			transitioning = true
			GameState.score += 38 + (GameState.level * 2)
			GameState.level += 1
			if GameState.light_durability > 0:
				GameState.has_light_source = true
			hud.log_message("You descend to level " + str(GameState.level) + "!", Color.GOLD)
			await fade_to_black()
			get_tree().reload_current_scene()
			
		if target_tile_type == GlobalEnums.TileType.ACID:
			acid_damage += acid_damage_unit
			hud.log_message("The acid eats at your spacesuit.", Color.GRAY)
			if acid_damage >= 1.0:
				GameState.player_hp -= 1
				acid_damage -= 1.0
				hud.log_message("You take acid damage!", Color.GREEN_YELLOW)
				if GameState.player_hp <= 0:
					player_death()

				
		
	# Light depletes on move
	if GameState.has_light_source and (dx != 0 or dy != 0):
		if GameState.level != 1: GameState.light_durability -= 1
		if GameState.light_durability <= 0:
			GameState.has_light_source = false
			hud.log_message("Your GLOW unit flickers and goes dark!", Color.RED)
	
	# Light flickers with depletion
	if GameState.has_light_source:
		var durability_percent = float(GameState.light_durability) / float(GameState.max_light_durability)
		if durability_percent > 0.18:
			$Timer.wait_time = 3.0
		else:
			var failing_percent = durability_percent / 0.18
			$Timer.wait_time = 0.2 + (failing_percent * 1.3)
	else: 
		$Timer.wait_time = 3.0
	
	# Environment
	update_fog()
	map_updated.emit()


func apply_item_effect(tile_def):
	var effect_data = tile_def.pickup_effect
	var effect_type = effect_data.effect
	var item_color = tile_def.color
	
	if effect_type == "heal":
		if GameState.player_hp < GameState.max_player_hp:
			GameState.player_hp = min(GameState.player_hp + effect_data.value, GameState.max_player_hp)
			if GameState.player_hp == GameState.max_player_hp:
				hud.log_message(effect_data.message["to_full"], item_color)
			else: 
				hud.log_message(effect_data.message["to_partial"], item_color)
		else:
			hud.log_message(effect_data.message["is_full"], item_color)
			return false
			
	elif effect_type == "increase_max_hp":
		GameState.max_player_hp += effect_data.value
		GameState.player_hp += effect_data.value
		hud.log_message(effect_data.message["default"], item_color)
		
	elif effect_type == "recharge_light":
		GameState.has_light_source = true
		GameState.max_light_durability = randi_range(GameState.max_light_durability * 0.75, GameState.max_light_durability * 1.5)
		GameState.light_durability = GameState.max_light_durability
		hud.log_message(effect_data.message["default"], item_color)
		$Timer.wait_time = 3.0
		
	return true


func pickup_item():
	var player_pos = Vector2(player.x, player.y)
	var tile_type = map_data[player_pos.y][player_pos.x]
	var tile_def = tile_data.get(tile_type)
	
	if tile_type in grabbable_items:
		if apply_item_effect(tile_def):
			map_data[player_pos.y][player_pos.x] = GlobalEnums.TileType.FLOOR
			tile_nodes[player_pos.y][player_pos.x].text = tile_data[GlobalEnums.TileType.FLOOR].char
			hud.get_node("ActionsLabel").hide()
			map_updated.emit()
			return true
		else:
			return false
	else:
		hud.log_message("There is nothing here to pick up.", Color.GRAY)
		return false


func enemy_take_turn(actor):
	var can_see_player = false
	var vision_radius = 6
	var actor_pos = Vector2(actor["x"], actor["y"])
	var player_pos = Vector2(player["x"], player["y"])
	var walkable_tiles = [GlobalEnums.TileType.FLOOR, GlobalEnums.TileType.ACID, GlobalEnums.TileType.CORPSE]
	
	if actor_pos.distance_to(player_pos) < vision_radius:
		can_see_player = true
	
	if can_see_player:
		var dx = player["x"] - actor["x"]
		var dy = player["y"] - actor["y"]
		
		if abs(dx) > abs(dy):
			dx = sign(dx)
			dy = 0
		else:
			dx = 0
			dy = sign(dy)
			
		var target_x = actor["x"] + dx
		var target_y = actor["y"] + dy
		var target_tile_type = map_data[target_y][target_x]
		
		if target_x == player["x"] and target_y == player["y"]:
			shake_camera()
			var hit_chance = randi_range(1, 100)
			if hit_chance <= actor["accuracy"] + GameState.level:
				GameState.player_hp -= 1
				hud.log_message("The alien attacks you! You have " + str(GameState.player_hp) + " HP left.", Color.RED)
				if GameState.player_hp <= 0:
					player_death()
			else:
				hud.log_message("The alien lunges at you and misses!", Color.GRAY)
		elif target_tile_type in walkable_tiles and not get_actor_at(target_x, target_y):
			actor["x"] = target_x
			actor["y"] = target_y
			actor["label"].position = Vector2(actor["x"] * tile_size, actor["y"] * tile_size)
		elif get_actor_at(target_x, target_y):
			var open_tiles = get_open_adjacent_tiles(actor["x"], actor["y"])
			if not open_tiles.is_empty():
				var new_pos = open_tiles[0]
				actor["x"] = new_pos.x
				actor["y"] = new_pos.y
				actor["label"].position = Vector2(actor["x"] * tile_size, actor["y"] * tile_size)


func get_open_adjacent_tiles(x, y):
	var open_tiles = []
	var directions = [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]
	directions.shuffle()
	
	for dir in directions:
		var adj_x = x + dir.x
		var adj_y = y + dir.y
		if map_data[adj_y][adj_x] != GlobalEnums.TileType.WALL and not get_actor_at(adj_x, adj_y):
			open_tiles.append(Vector2(adj_x, adj_y))
	return open_tiles


func kill_actor(actor):
	hud.log_message("The alien is defeated!", Color.LIGHT_GREEN)
	GameState.score += 9 + GameState.level
	var actor_pos = Vector2(actor.x, actor.y)
	map_data[actor_pos.y][actor_pos.x] = GlobalEnums.TileType.CORPSE
	tile_nodes[actor_pos.y][actor_pos.x].text = corpse_tile.char
	GameState.item_lore[actor_pos] = LoreManager.generate_alien_lore()
	actor.label.queue_free()
	actors.erase(actor)
	update_fog()
	map_updated.emit()


func player_death():
	game_over = true
	hud.log_message("You have been defeated!", Color.DARK_RED)
	is_player_turn = false
	
	if is_high_score():
		hud.get_node("EnterHighScorePanel").show()
	else:
		get_tree().paused = true
		hud.log_message("--- GAME OVER ---", Color.WHITE)
		hud.log_message("Press [R] to restart", Color.GRAY)


func shake_camera():
	var tween = create_tween()
	var shake_amount = 9
	var shake_duration = 0.18
	tween.tween_property(self, "position", self.position + Vector2(randi_range(-shake_amount, shake_amount), randi_range(-shake_amount, shake_amount)), shake_duration / 2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position", self.position, shake_duration / 2).set_trans(Tween.TRANS_SINE)


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


func spawn_actors_and_items():
	actors.clear()
	
	player = {
		"x": -1, "y": -1, "hp": GameState.player_hp,
		"char": player_stats.char, "color": player_stats.color, "accuracy": player_stats.accuracy
	}
	
	var player_placed = false
	while not player_placed:
		var px = randi_range(1, map_data[0].size() - 2)
		var py = randi_range(1, map_data.size() - 2)
		if map_data[py][px] == GlobalEnums.TileType.FLOOR and not get_actor_at(px, py):
			player["x"] = px
			player["y"] = py
			actors.append(player)
			player_placed = true

	var enemies_to_place = 2 + GameState.level
	for i in range(enemies_to_place):
		var enemy_placed = false
		while not enemy_placed:
			var ex = randi_range(1, map_data[0].size() - 2)
			var ey = randi_range(1, map_data.size() - 2)
			if map_data[ey][ex] == GlobalEnums.TileType.FLOOR and not get_actor_at(ex, ey):
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
	# Calculate the distance from the peak level for item distribution.
	var level_diff = abs(GameState.level - peak_armor_level)
	
	# This will hold the number of armor pieces that spawn this level, if any.
	var armor_placed_this_level = 0
	
	# 1. Determine the CHANCE and QUANTITY of ARMOR spawning.
	var armor_spawn_chance = max_armor_chance - (level_diff * armor_chance_falloff)
	var final_armor_chance = clamp(armor_spawn_chance, min_armor_chance, max_armor_chance)
	
	if randi_range(1, 100) <= final_armor_chance:
		var current_max_armor = max_armor_at_peak - (level_diff * armor_quantity_falloff)
		var current_min_armor = min_armor_at_peak - (level_diff * armor_quantity_falloff)
		
		var final_max_armor = clamp(current_max_armor, min_armor_to_place, max_armor_at_peak)
		var final_min_armor = clamp(current_min_armor, min_armor_to_place, max_armor_at_peak)
		
		armor_placed_this_level = randi_range(final_min_armor, final_max_armor)
		
		# Place the armor pieces.
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

	# 2. Determine the QUANTITY of HEALTH to spawn.
	# Always start with a base of 1 to guarantee at least one spawns.
	var health_to_place = 1
	
	# If armor also spawned, add a bonus amount of health.
	if armor_placed_this_level > 0:
		health_to_place += round(armor_placed_this_level * 0.75)
		
	# Clamp the final amount to ensure it doesn't exceed the maximum.
	health_to_place = clamp(health_to_place, 1, 4)

	# 3. Place the health items.
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


func create_actor_labels():
	for actor in actors:
		var new_label = Label.new()
		new_label.add_theme_font_override("font", tile_font)
		new_label.text = actor["char"]
		new_label.modulate = actor["color"]
		if actor == player:
			new_label.z_index = 10
		else:
			new_label.z_index = 5
			
			var enemy_health_bar = ProgressBar.new()
			enemy_health_bar.max_value = actor["hp"]
			enemy_health_bar.value = actor["hp"]
			enemy_health_bar.size = Vector2(tile_size, 5)
			enemy_health_bar.position = Vector2(0, -8)
			var style_box = StyleBoxFlat.new()
			style_box.bg_color = Color.RED
			enemy_health_bar.add_theme_stylebox_override("fill", style_box)
			enemy_health_bar.show_percentage = false
			enemy_health_bar.scale = Vector2(1, 0.1)
			new_label.add_child(enemy_health_bar)
			actor["health_bar"] = enemy_health_bar
		
		new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		new_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		new_label.size = Vector2(tile_size, tile_size)
		new_label.position = Vector2(actor["x"] * tile_size, actor["y"] * tile_size)
		add_child(new_label)
		actor["label"] = new_label


func update_fog():
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
					# If the player's personal light is out...
					if is_dark:
						# ...check if the current tile is a light crystal.
						if tile_type == GlobalEnums.TileType.LIGHT:
							# If it IS a light crystal, show its full color.
							tile_node.modulate = color
						else:
							# Otherwise, dim the tile to near-black.
							var brightness = color.v / 2.5
							tile_node.modulate = Color(brightness, brightness, brightness)
					else:
						# If the player has a light, show everything in full color.
						tile_node.modulate = color
			
			elif fog_state == GlobalEnums.FogState.KNOWN:
				# If the tile is a remembered light crystal...
				if tile_type == GlobalEnums.TileType.LIGHT:
					# ...show its color, but heavily dimmed.
					tile_node.modulate = tile_data[tile_type].color * Color(0.5, 0.5, 0.5)
				else:
					# Otherwise, show the standard dim grey for known tiles.
					tile_node.modulate = Color(0.2, 0.2, 0.2)
			
			else: # Hidden
				tile_node.modulate = Color(0, 0, 0)

	# --- PART 3: Update actor visuals ---
	#var player_pos = Vector2(player["x"], player["y"])
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


func _on_timer_timeout():
	if GameState.has_light_source and not GameState.is_flickering:
		var durability_percent = float(GameState.light_durability) / float(GameState.max_light_durability)
		if GameState.level == 1: durability_percent = 0.7
		var flicker_chance = 20 + (1.0 - durability_percent) * 60
		if randi_range(1, 100) <= flicker_chance:
			var flicker_duration = 0.15 + (1.0 - durability_percent) * 0.5
			GameState.is_flickering = true
			update_fog()
			map_updated.emit()
			await get_tree().create_timer(flicker_duration).timeout
			GameState.is_flickering = false
			if GameState.light_durability <= 0:
				GameState.has_light_source = false
			update_fog()
			map_updated.emit()


func is_high_score():
	if GameState.high_scores.size() < 10:
		return true
	var lowest_score = GameState.high_scores[-1]["score"]
	if GameState.score > lowest_score:
		return true
	return false


func fade_to_black():
	var tween = create_tween()
	tween.tween_property(hud.get_node("FadeOverlay"), "modulate", Color(1, 1, 1, 1), level_transition)
	await tween.finished


func fade_from_black():
	var tween = create_tween()
	var fadein = level_transition * 0.3
	hud.get_node("FadeOverlay").modulate = Color(1, 1, 1, 1)
	tween.tween_property(hud.get_node("FadeOverlay"), "modulate", Color(1, 1, 1, 0), fadein)
	await tween.finished
	hud.get_node("FadeOverlay").modulate = Color(1, 1, 1, 0)
	transitioning = false


func start_glow_effect():
	for y in range(map_data.size()):
		for x in range(map_data[y].size()):
			if map_data[y][x] == GlobalEnums.TileType.LIGHT:
				var crystal_label = tile_nodes[y][x]
				var tween = create_tween()
				tween.set_loops()
				tween.tween_property(crystal_label, "theme_override_colors/font_shadow_color", Color(1, 1, 0, 0.3), 1.5).set_trans(Tween.TRANS_SINE)
				tween.tween_property(crystal_label, "theme_override_colors/font_shadow_color", Color(1, 1, 0, 0), 1.5).set_trans(Tween.TRANS_SINE)


func examine_tile():
	var player_pos = Vector2(player.x, player.y)
	var tile_type = map_data[player_pos.y][player_pos.x]
	var pretext = "Examined item:"
	var message = "There is nothing to examine here."
	
	if hud.get_node("ExaminePanel").visible:
		hud.get_node("ExaminePanel").hide()
		return
	
	if tile_type in examinable_tiles:
		if tile_type == GlobalEnums.TileType.HP_UP:
			pretext = "According to the spacesuit data...\n\n"
			if GameState.item_lore.has(player_pos):
				var lore_text = GameState.item_lore[player_pos]
				message = pretext + str(lore_text)
			else:
				message = pretext + "The scout's corpse is too mangled to examine."
		if tile_type == GlobalEnums.TileType.CORPSE:
			pretext = "You examine the corpse...\n\n"
			if GameState.item_lore.has(player_pos):
				var lore_text = GameState.item_lore[player_pos]
				message = pretext + str(lore_text)
			else:
				message = pretext + "The corpse is too mangled to examine."

		hud.get_node("ExaminePanel/VBoxContainer/ExamineText").text = message
		hud.get_node("ExaminePanel").show()
	else:
		hud.log_message(message, Color.GRAY)


func _on_high_score_submitted(player_tag):
	if player_tag.length() > 3:
		player_tag = player_tag.substr(0, 3)
	while player_tag.length() < 3:
		player_tag += " "
	var new_score_entry = { "tag": player_tag, "score": GameState.score }
	GameState.high_scores.append(new_score_entry)
	GameState.high_scores.sort_custom(func(a, b): return a.score > b.score)
	if GameState.high_scores.size() > 10:
		GameState.high_scores.resize(10)
	GameState.save_high_scores()
	get_tree().paused = true
	hud.log_message("--- GAME OVER ---", Color.WHITE)
	hud.log_message("Press [R] to restart", Color.GRAY)


func _on_quit_to_menu_requested():
	game_is_paused = false
	get_tree().paused = false
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")
