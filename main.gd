extends Node2D

# --- Data Definitions ---
var tile_definitions = {
	0: { "char": ".", "color": Color("purple") },
	1: { "char": "#", "color": Color("blue_violet") },
	2: { "char": ">", "color": Color("gold") },
	5: { "char": "+", "color": Color("deep_sky_blue") },
	6: { "char": "&", "color": Color("sea_green") },
	7: { "char": "*", "color": Color("yellow") }
}

var actor_definitions = {
	"player": { "char": "@", "color": Color("cyan"), "hp": 10, "accuracy": 80 },
	"alien": { "char": "A", "color": Color("light_green"), "hp": 3, "accuracy": 32 }
}

# --- Game State Variables ---
var actors = []
var player
var tile_size = 24
var fog_map = []
var tile_nodes = []
var map_data = []
var is_player_turn = true

# --- Godot Functions ---
func _ready():
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
	update_fog()
	update_ui()


func _process(delta):
	if get_tree().paused and Input.is_action_just_pressed("restart"):
		# Reset game state for a new run
		GameState.score = 0
		GameState.level = 1
		GameState.player_hp = GameState.max_player_hp
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	
	if not get_tree().paused:
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
	elif target_tile_type != 1:
		if target_tile_type == 5:
			if player["hp"] < GameState.max_player_hp:
				player["hp"] += 4
				player["hp"] = min(player["hp"], GameState.max_player_hp)
				GameState.player_hp = player["hp"]
				log_message("You heal yourself", Color.DEEP_SKY_BLUE)
				update_ui()
				map_data[target_x][target_y] = 0
				tile_nodes[target_y][target_x].text = tile_definitions[0]["char"]
			else:
				log_message("You don't need health.", Color.GRAY)
				update_fog()
				return
		if target_tile_type == 6:
			GameState.max_player_hp += 1
			player["hp"] += 1
			player["hp"] = min(player["hp"], GameState.max_player_hp)
			log_message("You found a piece of armor", Color.SEA_GREEN)
			update_ui()
			map_data[target_x][target_y] = 0
			tile_nodes[target_y][target_x].text = tile_definitions[0]["char"]
		if target_tile_type == 7:
			GameState.has_light_source = true
			GameState.max_light_durability = randi_range(GameState.max_light_durability * 0.75, GameState.max_light_durability * 1.5)
			GameState.light_durability = GameState.max_light_durability
			log_message("You pick up a flashlight and turn it on.", Color.YELLOW)
			$Timer.wait_time = 3.0
			update_ui()
			map_data[target_x][target_y] = 0
			tile_nodes[target_y][target_x].text = tile_definitions[0]["char"]


		map_data[player["y"]][player["x"]] = 0
		player["x"] = target_x
		player["y"] = target_y
		map_data[player["y"]][player["x"]] = 4
		
		player["label"].position = Vector2(player["x"] * tile_size, player["y"] * tile_size)
		self.position = Vector2( -player["x"] * tile_size, -player["y"] * tile_size) + get_viewport_rect().size / 2
		
		if target_tile_type == 2:
			GameState.score += 38 + (GameState.level * 2)
			GameState.level += 1
			log_message("You descend to level " + str(GameState.level) + "!", Color.GOLD)
			get_tree().reload_current_scene()
		
	if GameState.has_light_source and (dx != 0 or dy != 0):
		GameState.light_durability -= 1
		if GameState.light_durability <= 0:
			GameState.has_light_source = false
			log_message("Your flashlight sputters and dies!", Color.RED)
		update_ui()
	
	if GameState.has_light_source:
		var durability_percent = float(GameState.light_durability) / float(GameState.max_light_durability)
		if durability_percent > 0.18:
			$Timer.wait_time = 3.0
		else:
			var failing_percent = durability_percent / 0.18
			$Timer.wait_time = 0.2 + (failing_percent * 1.3)
	else: 
		$Timer.wait_time = 3.0
	
	update_fog()


func enemy_take_turn(actor):
	var can_see_player = false
	var vision_radius = 5
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
		elif map_data[target_y][target_x] == 0:
			map_data[actor["y"]][actor["x"]] = 0
			actor["x"] = target_x
			actor["y"] = target_y
			map_data[actor["y"]][actor["x"]] = 3
			actor["label"].position = Vector2(actor["x"] * tile_size, actor["y"] * tile_size)


func kill_actor(actor):
	log_message("The alien is defeated!", Color.LIGHT_GREEN)
	GameState.score += 9 + GameState.level
	actor["char"] = "%"
	actor["color"] = Color("indigo")
	actor["hp"] = 0
	map_data[actor["y"]][actor["x"]] = 0
	update_ui()
	update_fog()


func player_death():
	log_message("You have been defeated!", Color.DARK_RED)
	is_player_turn = false
	get_tree().paused = true
	
	if GameState.score > GameState.high_score:
		GameState.high_score = GameState.score
		GameState.save_high_score()
		log_message("New High Score: " + str(GameState.high_score), Color.GOLD)
	
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
	health_label.text = "HP: " + str(player["hp"]) + " / " + str(GameState.max_player_hp) + "  |  Score: " + str(GameState.score) + "  |  High Score: " + str(GameState.high_score) + "  |  Level: " + str(GameState.level)
	
	var health_bar = $CanvasLayer/HealthBar
	health_bar.max_value = GameState.max_player_hp
	health_bar.value = player["hp"]


func log_message(message, color = Color.WHITE):
	var message_log = $CanvasLayer/MessageLog
	message_log.bbcode_enabled = true
	message_log.scroll_following = true
	message_log.append_text("[color=" + color.to_html() + "]" + message + "[/color]\n")


func generate_map():
	var width = 50
	var height = 50
	var new_map = []
	for y in range(height):
		var row = []
		for x in range(width):
			row.append(1)
		new_map.append(row)
	
	var digger_x = width / 2
	var digger_y = height / 2
	var steps_to_take = 2000
	for i in range(steps_to_take):
		new_map[digger_y][digger_x] = 0
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
	
	var player_def = actor_definitions["player"]
	player = {
		"x": -1, "y": -1, "hp": GameState.player_hp,
		"char": player_def["char"], "color": player_def["color"], "accuracy": player_def["accuracy"]
	}
	
	var player_placed = false
	while not player_placed:
		var px = randi_range(1, map_data[0].size() - 2)
		var py = randi_range(1, map_data.size() - 2)
		if map_data[py][px] == 0:
			player["x"] = px
			player["y"] = py
			actors.append(player)
			map_data[py][px] = 4
			player_placed = true

	var enemies_to_place = 2 + GameState.level
	for i in range(enemies_to_place):
		var enemy_placed = false
		while not enemy_placed:
			var ex = randi_range(1, map_data[0].size() - 2)
			var ey = randi_range(1, map_data.size() - 2)
			if map_data[ey][ex] == 0:
				var enemy_def = actor_definitions["alien"]
				actors.append({
					"x": ex, "y": ey, "hp": enemy_def["hp"],
					"char": enemy_def["char"], "color": enemy_def["color"], "accuracy": enemy_def["accuracy"]
				})
				map_data[ey][ex] = 3
				enemy_placed = true
	
	var staircase_placed = false
	while not staircase_placed:
		var sx = randi_range(1, map_data[0].size() - 2)
		var sy = randi_range(1, map_data.size() - 2)
		if map_data[sy][sx] == 0:
			map_data[sy][sx] = 2
			staircase_placed = true
	
	var potions_to_place = 1
	for i in range(potions_to_place):
		var potion_placed = false
		while not potion_placed:
			var px = randi_range(1, map_data[0].size() - 2)
			var py = randi_range(1, map_data.size() - 2)
			if map_data[py][px] == 0:
				map_data[py][px] = 5
				potion_placed = true

	var hp_chance = randi_range(1, 100)
	if hp_chance <= 25:
		var hp_to_place = 1
		for i in range(hp_to_place):
			var hp_placed = false
			while not hp_placed:
				var px = randi_range(1, map_data[0].size() - 2)
				var py = randi_range(1, map_data.size() - 2)
				if map_data[py][px] == 0:
					map_data[py][px] = 6
					hp_placed = true

	var flashlight_chance = 100
	if GameState.level > 1:
		flashlight_chance = max(25, 100 - ((GameState.level - 1) * 8))
	if randi_range(1, 100) <= flashlight_chance:
		var flashlight_placed = false
		while not flashlight_placed:
			var px = randi_range(1, map_data[0].size() - 2)
			var py = randi_range(1, map_data.size() - 2)
			if map_data[py][px] == 0:
				map_data[py][px] = 7
				flashlight_placed = true


func create_map_tiles():
	fog_map.clear()
	tile_nodes.clear()
	for y in range(map_data.size()):
		var node_row = []
		var fog_row = []
		for x in range(map_data[y].size()):
			fog_row.append(0)
			var tile_type = map_data[y][x]
			var new_tile = Label.new()
			if tile_definitions.has(tile_type):
				var tile_def = tile_definitions[tile_type]
				new_tile.text = tile_def["char"]
			else:
				new_tile.text = tile_definitions[0]["char"]
			
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
	# First, set all currently 'visible' (2) tiles back to 'known' (1)
	for y in range(fog_map.size()):
		for x in range(fog_map[y].size()):
			if fog_map[y][x] == 2:
				fog_map[y][x] = 1

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
					fog_map[y][x] = 2

	# --- PART 2: Update the visuals ---
	# Update map tile visuals
	for y in range(map_data.size()):
		for x in range(map_data[y].size()):
			var fog_state = fog_map[y][x]
			var tile_node = tile_nodes[y][x]
			if fog_state == 2: # Visible
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
			elif fog_state == 1: # Known
				tile_node.modulate = Color(0.2, 0.2, 0.2)
			else: # Hidden
				tile_node.modulate = Color(0, 0, 0)

	# Part 3: Update actor visuals
	for actor in actors:
		var fog_state = fog_map[actor["y"]][actor["x"]]
		var actor_pos = Vector2(actor["x"], actor["y"])
		
		if fog_state == 2: # Actor is in a visible tile
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
		elif fog_state == 1: # In a known area
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
			var flicker_duration = 0.2 + (1.0 - durability_percent) * 0.5
			GameState.has_light_source = false
			update_fog()
			await get_tree().create_timer(flicker_duration).timeout
			GameState.has_light_source = true
			update_fog()
