extends Node2D

signal map_updated

# --- Data Definitions ---
var tile_definitions = {
	GlobalEnums.TileType.FLOOR: { 
		"char": ".", 
		"color": Color("purple"), 
		"is_item": false
	},
	GlobalEnums.TileType.WALL: { 
		"char": "#", 
		"color": Color("blue_violet"), 
		"is_item": false
	},
	GlobalEnums.TileType.STAIRS: { 
		"char": ">", 
		"color": Color("orange"), 
		"is_item": false
	},
	GlobalEnums.TileType.HEALTH: { 
		"char": "+", 
		"color": Color("deep_sky_blue"), 
		"is_item": true,
		"pickup_method": "auto",
		"on_pickup": {
			"effect": "heal",
			"value": 5,
			"message": {
				"to_partial": "You partially repair your spacesuit.",
				"to_full": "You fully repair your spacesuit.",
				"is_full": "Your spacesuit doesn't need repairs."
			}
		}
	},
	GlobalEnums.TileType.HP_UP: { 
		"char": "&", 
		"color": Color("sea_green"), 
		"is_item": true,
		"pickup_method": "manual",
		"on_pickup": {
			"effect": "increase_max_hp",
			"value": 1,
			"message": {
				"default": "You scavenge a piece of armor."
			}
		}
	},
	GlobalEnums.TileType.LIGHT: { 
		"char": "*", 
		"color": Color("yellow"), 
		"is_item": true,
		"pickup_method": "auto",
		"on_pickup": {
			"effect": "recharge_light",
			"message": {
				"default": "You pick up a crystal and recharge your GLOW unit."
			}
		}
	}
}

var actor_definitions = {
	GlobalEnums.ActorType.PLAYER: { 
		"char": "@", 
		"color": Color("cyan"), 
		"hp": 10, 
		"accuracy": 80 
	},
	GlobalEnums.ActorType.ALIEN: { 
		"char": "A", 
		"color": Color("light_green"), 
		"hp": 3, 
		"accuracy": 32 
	}
}

# --- Game State Variables ---
var actors = []
var player
var tile_size = 24
var fog_map = []
var tile_nodes = []
var map_data = []
var message_history = []

var peak_armor_level = 5
var max_armor_chance = 90
var min_armor_chance = 25
var armor_chance_falloff = 15
var min_armor_at_peak = 4
var max_armor_at_peak = 8
var min_armor_to_place = 1
var armor_quantity_falloff = 2

var is_player_turn = true
var light_dur_init = GameState.light_durability
var max_light_dur_init = GameState.max_light_durability
var game_is_paused = false
var tile_font = preload("res://fonts/SpaceMono-Regular.ttf")
var level_transition = 2.0
var transitioning = false

# --- Godot Functions ---
func _ready():
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
	update_ui()
	map_updated.emit()


func _process(delta):
	if get_tree().paused and Input.is_action_just_pressed("restart"):
		# Reset game state for a new run
		GameState.score = 0
		GameState.level = 1
		GameState.max_player_hp = 10
		GameState.player_hp = GameState.max_player_hp
		GameState.has_light_source = true
		GameState.light_durability = light_dur_init
		GameState.max_light_durability = max_light_dur_init
		GameState.item_lore.clear()
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	
	if Input.is_action_just_pressed("ui_cancel"):
		game_is_paused = not game_is_paused
		$CanvasLayer/QuitDialogue.visible = game_is_paused
	
	if not get_tree().paused and not game_is_paused and not transitioning:
		
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


# --- Custom Game Logic Functions ---
func try_move(dx, dy):
	var target_x = player["x"] + dx
	var target_y = player["y"] + dy
	var target_tile_type = map_data[target_y][target_x]

	var target_actor = null
	for actor in actors:
		if actor["x"] == target_x and actor["y"] == target_y:
			target_actor = actor
			break
	
	# Combat
	if target_actor != null and target_actor != player and target_actor["hp"] > 0:
		shake_camera()
		var hit_chance = randi_range(1, 100)
		if hit_chance <= player["accuracy"]:
			target_actor["hp"] -= 1
			target_actor["health_bar"].value = target_actor["hp"]
			log_message("You hit the alien! It has " + str(target_actor["hp"]) + " HP left.", Color.ORANGE)
			if target_actor["hp"] <= 0:
				kill_actor(target_actor)
		else:
			log_message("You swing at the alien and miss!", Color.GRAY)
	# Non-combat
	elif target_tile_type != GlobalEnums.TileType.WALL:
		var tile_def = tile_definitions.get(target_tile_type)
		var moved = true
		if tile_def and tile_def.get("pickup_method") == "auto":
			if apply_item_effect(tile_def):
				map_data[target_y][target_x] = GlobalEnums.TileType.FLOOR
				tile_nodes[target_y][target_x].text = tile_definitions[GlobalEnums.TileType.FLOOR]["char"]
				map_updated.emit()
			else:
				moved = false
				return
		if moved:
			player["x"] = target_x
			player["y"] = target_y
			player["label"].position = Vector2(player["x"] * tile_size, player["y"] * tile_size)
			self.position = Vector2( -player["x"] * tile_size, -player["y"] * tile_size) + get_viewport_rect().size / 2
			if tile_def and tile_def.get("pickup_method") == "manual":
				$CanvasLayer/ActionsLabel.show()
			else: 
				$CanvasLayer/ActionsLabel.hide()
		
		if target_tile_type == GlobalEnums.TileType.STAIRS:
			transitioning = true
			GameState.score += 38 + (GameState.level * 2)
			GameState.level += 1
			if GameState.light_durability > 0:
				GameState.has_light_source = true
			log_message("You descend to level " + str(GameState.level) + "!", Color.GOLD)
			await fade_to_black()
			get_tree().reload_current_scene()
		
	# Light depletes on move
	if GameState.has_light_source and (dx != 0 or dy != 0):
		GameState.light_durability -= 1
		if GameState.light_durability <= 0:
			GameState.has_light_source = false
			log_message("Your GLOW unit flickers and goes dark!", Color.RED)
		update_ui()
	
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
	var effect_data = tile_def.on_pickup
	var effect_type = effect_data.effect
	var item_color = tile_def.color
	
	if effect_type == "heal":
		if player["hp"] < GameState.max_player_hp:
			player["hp"] = min(player["hp"] + effect_data.value, GameState.max_player_hp)
			GameState.player_hp = player["hp"]
			if GameState.player_hp == GameState.max_player_hp:
				log_message(effect_data.message.to_full, item_color)
			else: 
				log_message(effect_data.message.to_partial, item_color)
		else:
			log_message(effect_data.message.is_full, item_color)
			return false
			
	elif effect_type == "increase_max_hp":
		GameState.max_player_hp += effect_data.value
		player["hp"] += effect_data.value
		log_message(effect_data.message.default, item_color)
		
	elif effect_type == "recharge_light":
		GameState.has_light_source = true
		GameState.max_light_durability = randi_range(GameState.max_light_durability * 0.75, GameState.max_light_durability * 1.5)
		GameState.light_durability = GameState.max_light_durability
		log_message(effect_data.message.default, item_color)
		$Timer.wait_time = 3.0
		
	update_ui()
	return true


func pickup_item():
	var player_pos = Vector2i(player.x, player.y)
	var tile_type = map_data[player_pos.y][player_pos.x]
	var tile_def = tile_definitions.get(tile_type)
	
	if tile_def and tile_def.get("pickup_method") == "manual":
		if apply_item_effect(tile_def):
			map_data[player_pos.y][player_pos.x] = GlobalEnums.TileType.FLOOR
			tile_nodes[player_pos.y][player_pos.x].text = tile_definitions[GlobalEnums.TileType.FLOOR]["char"]
			$CanvasLayer/ActionsLabel.hide()
			map_updated.emit()
			return true
		else:
			return false
	else:
		log_message("There is nothing here to pick up.", Color.GRAY)
		return false


func enemy_take_turn(actor):
	var can_see_player = false
	var vision_radius = 6
	var actor_pos = Vector2(actor["x"], actor["y"])
	var player_pos = Vector2(player["x"], player["y"])
	
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
		
		if target_x == player["x"] and target_y == player["y"]:
			shake_camera()
			var hit_chance = randi_range(1, 100)
			if hit_chance <= actor["accuracy"] + GameState.level:
				player["hp"] -= 1
				GameState.player_hp = player["hp"]
				log_message("The alien attacks you! You have " + str(player["hp"]) + " HP left.", Color.RED)
				update_ui()
				if player["hp"] <= 0:
					player_death()
			else:
				log_message("The alien lunges at you and misses!", Color.GRAY)
		elif map_data[target_y][target_x] == GlobalEnums.TileType.FLOOR:
			actor["x"] = target_x
			actor["y"] = target_y
			actor["label"].position = Vector2(actor["x"] * tile_size, actor["y"] * tile_size)


func kill_actor(actor):
	log_message("The alien is defeated!", Color.LIGHT_GREEN)
	GameState.score += 9 + GameState.level
	actor["char"] = "%"
	actor["color"] = Color("indigo")
	actor["hp"] = 0
	map_data[actor["y"]][actor["x"]] = GlobalEnums.TileType.FLOOR
	update_ui()
	update_fog()
	map_updated.emit()


func player_death():
	log_message("You have been defeated!", Color.DARK_RED)
	is_player_turn = false
	
	if is_high_score():
		$CanvasLayer/EnterHighScorePanel.show()
	else:
		get_tree().paused = true
		log_message("--- GAME OVER ---", Color.WHITE)
		log_message("Press [R] to restart", Color.GRAY)


func shake_camera():
	var tween = create_tween()
	var shake_amount = 9
	var shake_duration = 0.18
	tween.tween_property(self, "position", self.position + Vector2(randi_range(-shake_amount, shake_amount), randi_range(-shake_amount, shake_amount)), shake_duration / 2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position", self.position, shake_duration / 2).set_trans(Tween.TRANS_SINE)


func update_ui():
	var health_label = $CanvasLayer/HealthLabel
	var top_score = 0
	if not GameState.high_scores.is_empty():
		top_score = GameState.high_scores[0]["score"]
	health_label.text = "HP: " + str(player["hp"]) + " / " + str(GameState.max_player_hp) + "  |  Score: " + str(GameState.score) + "  |  High Score: " + str(top_score) + "  |  Level: " + str(GameState.level)# + "  |  FL: " + str(GameState.light_durability) + "/" + str(GameState.max_light_durability)
	
	var health_bar = $CanvasLayer/HealthBar
	health_bar.max_value = GameState.max_player_hp
	health_bar.value = player["hp"]


func log_message(message, color = Color.WHITE):
	message_history.append({ "text": message, "color": color })
	if message_history.size() > 10:
		message_history.pop_front()
	var message_log = $CanvasLayer/MessageLog
	message_log.clear()
	for i in range(message_history.size()):
		var msg_data = message_history[i]
		var text = msg_data["text"]
		var text_color = msg_data["color"]
		if i < message_history.size() - 1:
			text_color.a = 0.5
		message_log.bbcode_enabled = true
		message_log.scroll_following = true
		message_log.append_text("[color=" + text_color.to_html(true) + "]" + text + "[/color]\n")


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
	
	var player_def = actor_definitions[GlobalEnums.ActorType.PLAYER]
	player = {
		"x": -1, "y": -1, "hp": GameState.player_hp,
		"char": player_def["char"], "color": player_def["color"], "accuracy": player_def["accuracy"]
	}
	
	var player_placed = false
	while not player_placed:
		var px = randi_range(1, map_data[0].size() - 2)
		var py = randi_range(1, map_data.size() - 2)
		if map_data[py][px] == GlobalEnums.TileType.FLOOR:
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
			if map_data[ey][ex] == GlobalEnums.TileType.FLOOR:
				var enemy_def = actor_definitions[GlobalEnums.ActorType.ALIEN]
				actors.append({
					"x": ex, "y": ey, "hp": enemy_def["hp"],
					"char": enemy_def["char"], "color": enemy_def["color"], "accuracy": enemy_def["accuracy"]
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
		
	# 1. Determine the CHANCE of spawning a cluster of items (armor and health).
	var calculated_chance = max_armor_chance - (level_diff * armor_chance_falloff)
	var final_chance = clamp(calculated_chance, min_armor_chance, max_armor_chance)
		
	if randi_range(1, 100) <= final_chance:
		# 2. If the chance succeeds, first determine the QUANTITY of ARMOR to place.
		var current_max_armor = max_armor_at_peak - (level_diff * armor_quantity_falloff)
		var current_min_armor = min_armor_at_peak - (level_diff * armor_quantity_falloff)
			
		var final_max_armor = clamp(current_max_armor, min_armor_to_place, max_armor_at_peak)
		var final_min_armor = clamp(current_min_armor, min_armor_to_place, max_armor_at_peak)
			
		var armor_to_place = randi_range(final_min_armor, final_max_armor)
			
		# 3. THEN, calculate the QUANTITY of HEALTH based on the amount of armor.
		# It will be 75% of the armor amount, clamped between 1 and 4.
		var health_to_place = clamp(round(armor_to_place * 0.75), 1, 4)

		# 4. Place the calculated number of HEALTH items.
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
			
		# 5. Finally, place the calculated number of ARMOR items.
		for i in range(armor_to_place):
			var hp_placed = false
			var placement_attempts = 0
			while not hp_placed and placement_attempts < 100:
				var px = randi_range(1, map_data[0].size() - 2)
				var py = randi_range(1, map_data.size() - 2)
				if map_data[py][px] == GlobalEnums.TileType.FLOOR:
					map_data[py][px] = GlobalEnums.TileType.HP_UP
						
					var item_position = Vector2i(px, py)
					GameState.item_lore[item_position] = LoreManager.generate_scout_lore()
						
					hp_placed = true
				placement_attempts += 1
	

	var light_chance = 100
	if GameState.level > 1:
		light_chance = max(25, 100 - ((GameState.level - 1) * 8))
	if randi_range(1, 100) <= light_chance:
		var light_placed = false
		while not light_placed:
			var px = randi_range(1, map_data[0].size() - 2)
			var py = randi_range(1, map_data.size() - 2)
			if map_data[py][px] == GlobalEnums.TileType.FLOOR:
				map_data[py][px] = GlobalEnums.TileType.LIGHT
				light_placed = true


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
			if tile_definitions.has(tile_type):
				var tile_def = tile_definitions[tile_type]
				new_tile.text = tile_def["char"]
			else:
				new_tile.text = tile_definitions[GlobalEnums.TileType.FLOOR]["char"]
				
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

	# Then, calculate the new visible area based on whether we have a light
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

	# --- PART 2: Update the visuals ---
	# Update map tile visuals
	for y in range(map_data.size()):
		for x in range(map_data[y].size()):
			var fog_state = fog_map[y][x]
			var tile_node = tile_nodes[y][x]
			if fog_state == GlobalEnums.FogState.VISIBLE:
				var tile_type = map_data[y][x]
				if tile_definitions.has(tile_type):
					var color = tile_definitions[tile_type]["color"]
					if not GameState.has_light_source:
						# In dark mode, desaturate the color
						var brightness = color.v / 2.5
						tile_node.modulate = Color(brightness, brightness, brightness)
					else:
						# With a light, show full color
						tile_node.modulate = color
			elif fog_state == GlobalEnums.FogState.KNOWN: 
				tile_node.modulate = Color(0.2, 0.2, 0.2)
			else: # Hidden
				tile_node.modulate = Color(0, 0, 0)

	# Part 3: Update actor visuals
	for actor in actors:
		var fog_state = fog_map[actor["y"]][actor["x"]]
		var actor_pos = Vector2(actor["x"], actor["y"])
		
		if fog_state == GlobalEnums.FogState.VISIBLE:
			if not GameState.has_light_source and actor != player:
				# In dark mode, only see aliens if they are right next to you
				if player_pos.distance_to(actor_pos) <= 1.5:
					actor["label"].visible = true
				else:
					actor["label"].visible = false
			else:
				# With a light, or if it's the player, they are visible
				actor["label"].visible = true
			
			actor["label"].text = actor["char"]
			actor["label"].modulate = actor["color"]
		elif fog_state == GlobalEnums.FogState.KNOWN:
			if actor["hp"] <= 0: # If it's a corpse
				actor["label"].visible = true
				actor["label"].text = actor["char"]
				actor["label"].modulate = Color(0.2, 0.2, 0.2)
			else: # It's a living enemy, hide it
				actor["label"].visible = false
		else: # In a hidden area
			actor["label"].visible = false


func _on_timer_timeout():
	if GameState.has_light_source:
		var durability_percent = float(GameState.light_durability) / float(GameState.max_light_durability)
		var flicker_chance = 20 + (1.0 - durability_percent) * 60
		if randi_range(1, 100) <= flicker_chance:
			var flicker_duration = 0.15 + (1.0 - durability_percent) * 0.5
			GameState.has_light_source = false
			update_fog()
			map_updated.emit()
			await get_tree().create_timer(flicker_duration).timeout
			GameState.has_light_source = true
			update_fog()
			map_updated.emit()


func is_high_score():
	if GameState.high_scores.size() < 10:
		return true
	var lowest_score = GameState.high_scores[-1]["score"]
	if GameState.score > lowest_score:
		return true
	return false


func _on_submit_hs_pressed() -> void:
	var line_edit = $CanvasLayer/EnterHighScorePanel/VBoxContainer/LineEdit
	var player_tag = line_edit.text.to_upper()
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
	$CanvasLayer/EnterHighScorePanel.hide()
	get_tree().paused = true
	log_message("--- GAME OVER ---", Color.WHITE)
	log_message("Press [R] to restart", Color.GRAY)


func _on_yes_quit_pressed() -> void:
	game_is_paused = false
	get_tree().paused = false
	GameState.score = 0
	GameState.level = 1
	GameState.max_player_hp = 10
	GameState.player_hp = GameState.max_player_hp
	GameState.has_light_source = true
	GameState.light_durability = light_dur_init
	GameState.max_light_durability = max_light_dur_init
	GameState.item_lore.clear()
	get_tree().change_scene_to_file("res://TitleScreen.tscn")


func _on_no_quit_pressed() -> void:
	game_is_paused = false
	$CanvasLayer/QuitDialogue.hide()


func fade_to_black():
	var tween = create_tween()
	tween.tween_property($CanvasLayer/FadeOverlay, "modulate", Color(1, 1, 1, 1), level_transition)
	await tween.finished


func fade_from_black():
	var tween = create_tween()
	var fadein = level_transition * 0.3
	$CanvasLayer/FadeOverlay.modulate = Color(1, 1, 1, 1)
	tween.tween_property($CanvasLayer/FadeOverlay, "modulate", Color(1, 1, 1, 0), fadein)
	await tween.finished
	$CanvasLayer/FadeOverlay.modulate = Color(1, 1, 1, 0)
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
	var message = "There is nothing to examine here."
	
	if $CanvasLayer/ExaminePanel.visible:
		$CanvasLayer/ExaminePanel.hide()
		return
	
	if tile_type == GlobalEnums.TileType.HP_UP:
		var pretext = "According to the spacesuit data...\n\n"
		if GameState.item_lore.has(player_pos):
			var lore_text = GameState.item_lore[player_pos]
			message = pretext + str(lore_text)
		else:
			message = pretext + "The scout's corpse is too mangled to examine."
		$CanvasLayer/ExaminePanel/VBoxContainer/ExamineText.text = message
		$CanvasLayer/ExaminePanel.show()
	else:
		log_message(message, Color.GRAY)


func _on_ok_pressed() -> void:
	$CanvasLayer/ExaminePanel.hide()
