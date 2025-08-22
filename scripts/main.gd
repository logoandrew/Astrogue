extends Node2D

@export var acid_damage_unit = 0.334
var acid_damage = 0.0

@onready var hud = $HUD
@onready var map = $Map

var actors = []
var player
var is_player_turn = true
var transitioning = false
var game_is_paused = false
var game_over = false


# --- Godot Functions ---
func _ready():
	# 1. Initialize actors
	player = {
		"x": -1, "y": -1, "hp": map.player_stats.hp,
		"char": map.player_stats.char, "color": map.player_stats.color, "accuracy": map.player_stats.accuracy, "damage": map.player_stats.damage
	}
	actors.append(player)
	GameState.player_hp = map.player_stats.hp
	GameState.max_player_hp = map.player_stats.hp
	
	# 2. Spawn actors and items on the map
	map.spawn_actors_and_items(actors)
	
	# 3. Create the visual labels
	map.create_map_tiles()
	create_actor_labels()
	map.start_glow_effect()
	
	# 4. Center the camera on the player
	var player_pixel_pos = player["label"].position
	var screen_center = get_viewport_rect().size / 2
	self.position = screen_center - player_pixel_pos
	
	# 5. Set the initial fog of war and UI
	map.update_fog(player, actors)
	map.map_updated.emit()
	hud.quit_to_menu_requested.connect(_on_quit_to_menu_requested)
	hud.high_score_submitted.connect(_on_high_score_submitted)
	GameState.connect("inventory_changed", _on_inventory_changed)
	
	fade_from_black()


func _process(delta):
	if get_tree().paused and Input.is_action_just_pressed("restart"):
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
			for i in range(actors.size() - 1, 0, -1):
				var actor = actors[i]
				if actor["hp"] > 0:
					enemy_take_turn(actor)
					
			is_player_turn = true


func _draw():
	var grid_range = 50
	for i in range(-grid_range, grid_range + 1):
		var x = i * map.tile_size
		draw_line(Vector2(x, -grid_range * map.tile_size), Vector2(x, grid_range * map.tile_size), DesignSystem.COLOR_GRID)
	
	for i in range(-grid_range, grid_range + 1):
		var y = i * map.tile_size
		draw_line(Vector2(-grid_range * map.tile_size, y), Vector2(grid_range * map.tile_size, y), DesignSystem.COLOR_GRID)


func get_actor_at(x, y):
	for actor in actors:
		if actor["x"] == x and actor["y"] == y:
			return actor
	return null


func try_move(dx, dy):
	var target_x = player["x"] + dx
	var target_y = player["y"] + dy
	
	var target_actor = get_actor_at(target_x, target_y)
	var target_tile_type = map.map_data[target_y][target_x]
	
	# Combat
	if target_actor != null and target_actor != player:
		shake_camera()
		if GameState.melee_slot:
			GameState.melee_slot_uses -= 1
			if GameState.melee_slot_uses <= 0:
				GameState.melee_slot = false
				hud.log_message("Your melee crystal shatters!", DesignSystem.COLOR_DANGER)
				GameState.emit_signal("inventory_changed")
		var hit_chance = randi_range(1, 100)
		if hit_chance <= player["accuracy"]:
			var current_damage = player.get("damage", 1)
			if GameState.melee_slot:
				current_damage += 2
			target_actor.hp -= current_damage
			target_actor.health_bar.value = target_actor.hp
			hud.log_message("You hit the alien! It has " + str(target_actor.hp) + " HP left.")
			if target_actor.hp <= 0:
				kill_actor(target_actor)
		else:
			hud.log_message("You swing at the alien and miss!", DesignSystem.COLOR_TEXT_SECONDARY)
	# Non-combat
	elif target_tile_type != GlobalEnums.TileType.WALL:
		var tile_def = map.tile_data.get(target_tile_type)
		var moved = true
		if tile_def and tile_def.pickup_method == "auto":
			if apply_item_effect(tile_def):
				map.map_data[target_y][target_x] = GlobalEnums.TileType.FLOOR
				map.tile_nodes[target_y][target_x].text = map.tile_data[GlobalEnums.TileType.FLOOR].char
				map.map_updated.emit()
			else:
				moved = false
				return
		if moved:
			player["x"] = target_x
			player["y"] = target_y
			player["label"].position = Vector2(player["x"] * map.tile_size, player["y"] * map.tile_size)
			self.position = Vector2( -player["x"] * map.tile_size, -player["y"] * map.tile_size) + get_viewport_rect().size / 2
			
			var current_tile_type = map.map_data[player.y][player.x]
			var available_actions = []
			if current_tile_type in map.examinable_tiles:
				available_actions.append("Press [e] to examine")
			if current_tile_type in map.grabbable_items:
				available_actions.append("Press [g] to pickup")
			if not available_actions.is_empty():
				hud.get_node("ActionsLabel").text = "  |  ".join(available_actions)
				hud.get_node("ActionsLabel").show()
			else: 
				hud.get_node("ActionsLabel").hide()
		
		if target_tile_type == GlobalEnums.TileType.STAIRS:
			$Timer.stop()
			GameState.is_flickering = false
			if GameState.light_durability > 0 and GameState.light_durability < 10:
				GameState.light_durability += 10
			transitioning = true
			GameState.score += 38 + (GameState.level * 2)
			GameState.level += 1
			hud.log_message("You descend to level " + str(GameState.level) + "!", DesignSystem.COLOR_ACCENT)
			await fade_to_black()
			get_tree().reload_current_scene()
			
		if target_tile_type == GlobalEnums.TileType.ACID:
			acid_damage += acid_damage_unit
			hud.log_message("The acid eats at your spacesuit.", DesignSystem.COLOR_TEXT_SECONDARY)
			if acid_damage >= 1.0:
				GameState.player_hp -= 1
				acid_damage -= 1.0
				hud.log_message("You take acid damage!", DesignSystem.COLOR_DANGER)
				if GameState.player_hp <= 0:
					player_death()
	
	if GameState.glow_slot and (dx != 0 or dy != 0):
		if GameState.level != 1: GameState.light_durability -= 1
		if GameState.light_durability <= 0:
			GameState.glow_slot = false
			hud.log_message("Your GLOW unit flickers and goes dark!", DesignSystem.COLOR_DANGER)
			GameState.emit_signal("inventory_changed")
	
	if GameState.glow_slot:
		var durability_percent = float(GameState.light_durability) / float(GameState.max_light_durability)
		if durability_percent > 0.18:
			$Timer.wait_time = 3.0
		else:
			var failing_percent = durability_percent / 0.18
			$Timer.wait_time = 0.2 + (failing_percent * 1.3)
	else: 
		$Timer.wait_time = 3.0
	
	map.update_fog(player, actors)
	map.map_updated.emit()


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
		
	elif effect_type == "add_crystal":
		GameState.crystal_inventory.append(randi_range(GameState.max_light_durability * 0.8, GameState.max_light_durability * 1.4))
		hud.log_message(effect_data.message["default"], item_color)
		GameState.emit_signal("inventory_changed")
		
	elif effect_type == "recharge_light":
		GameState.glow_slot = true
		GameState.max_light_durability = randi_range(GameState.max_light_durability * 0.8, GameState.max_light_durability * 1.4)
		GameState.light_durability = GameState.max_light_durability
		hud.log_message(effect_data.message["default"], item_color)
		$Timer.wait_time = 3.0
		GameState.emit_signal("inventory_changed")
		
	return true


func pickup_item():
	var player_pos = Vector2(player.x, player.y)
	var tile_type = map.map_data[player_pos.y][player_pos.x]
	var tile_def = map.tile_data.get(tile_type)
	
	if tile_type in map.grabbable_items:
		if apply_item_effect(tile_def):
			map.map_data[player_pos.y][player_pos.x] = GlobalEnums.TileType.FLOOR
			map.tile_nodes[player_pos.y][player_pos.x].text = map.tile_data[GlobalEnums.TileType.FLOOR].char
			hud.get_node("ActionsLabel").hide()
			map.map_updated.emit()
			return true
		else:
			return false
	else:
		hud.log_message("There is nothing here to pick up.", DesignSystem.COLOR_TEXT_SECONDARY)
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
		var target_tile_type = map.map_data[target_y][target_x]
		
		if target_x == player["x"] and target_y == player["y"]:
			shake_camera()
			var hit_chance = randi_range(1, 100)
			if hit_chance <= actor["accuracy"] + GameState.level:
				GameState.player_hp -= 1
				hud.log_message("The alien attacks you! You have " + str(GameState.player_hp) + " HP left.", DesignSystem.COLOR_DANGER)
				if GameState.player_hp <= 0:
					player_death()
			else:
				hud.log_message("The alien lunges at you and misses!", DesignSystem.COLOR_TEXT_SECONDARY)
		elif target_tile_type in walkable_tiles and not get_actor_at(target_x, target_y):
			actor["x"] = target_x
			actor["y"] = target_y
			actor["label"].position = Vector2(actor["x"] * map.tile_size, actor["y"] * map.tile_size)
		elif get_actor_at(target_x, target_y):
			var open_tiles = map.get_open_adjacent_tiles(actor["x"], actor["y"])
			if not open_tiles.is_empty():
				var new_pos = open_tiles[0]
				actor["x"] = new_pos.x
				actor["y"] = new_pos.y
				actor["label"].position = Vector2(actor["x"] * map.tile_size, actor["y"] * map.tile_size)


func kill_actor(actor):
	hud.log_message("The alien is defeated!", DesignSystem.COLOR_ACCENT)
	GameState.score += 9 + GameState.level
	var actor_pos = Vector2(actor.x, actor.y)
	map.map_data[actor_pos.y][actor_pos.x] = GlobalEnums.TileType.CORPSE
	map.tile_nodes[actor_pos.y][actor_pos.x].text = map.corpse_tile.char
	GameState.item_lore[actor_pos] = LoreManager.generate_alien_lore()
	actor.label.queue_free()
	actors.erase(actor)
	map.update_fog(player, actors)
	map.map_updated.emit()


func player_death():
	game_over = true
	hud.log_message("You have been defeated!", DesignSystem.COLOR_DANGER)
	is_player_turn = false
	
	if is_high_score():
		hud.get_node("EnterHighScorePanel").show()
	else:
		get_tree().paused = true
		hud.log_message("--- GAME OVER ---")
		hud.log_message("Press [R] to restart")


func shake_camera():
	var tween = create_tween()
	var shake_amount = 9
	var shake_duration = 0.18
	tween.tween_property(self, "position", self.position + Vector2(randi_range(-shake_amount, shake_amount), randi_range(-shake_amount, shake_amount)), shake_duration / 2).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position", self.position, shake_duration / 2).set_trans(Tween.TRANS_SINE)

func create_actor_labels():
	for actor in actors:
		var new_label = Label.new()
		new_label.add_theme_font_override("font", map.tile_font)
		new_label.text = actor["char"]
		new_label.modulate = actor["color"]
		if actor == player:
			new_label.z_index = 10
		else:
			new_label.z_index = 5
			
			var enemy_health_bar = ProgressBar.new()
			enemy_health_bar.max_value = actor["hp"]
			enemy_health_bar.value = actor["hp"]
			enemy_health_bar.size = Vector2(map.tile_size, 5)
			enemy_health_bar.position = Vector2(0, -8)
			var style_box = StyleBoxFlat.new()
			style_box.bg_color = DesignSystem.COLOR_DANGER
			enemy_health_bar.add_theme_stylebox_override("fill", style_box)
			enemy_health_bar.show_percentage = false
			enemy_health_bar.scale = Vector2(1, 0.1)
			new_label.add_child(enemy_health_bar)
			actor["health_bar"] = enemy_health_bar
		
		new_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		new_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		new_label.size = Vector2(map.tile_size, map.tile_size)
		new_label.position = Vector2(actor["x"] * map.tile_size, actor["y"] * map.tile_size)
		add_child(new_label)
		actor["label"] = new_label


func _on_timer_timeout():
	if GameState.has_light_source() and not GameState.is_flickering:
		var durability_percent = float(GameState.light_durability) / float(GameState.max_light_durability)
		if GameState.level == 1: durability_percent = 0.7
		var flicker_chance = 20 + (1.0 - durability_percent) * 60
		if randi_range(1, 100) <= flicker_chance:
			var flicker_duration = 0.15 + (1.0 - durability_percent) * 0.5
			GameState.is_flickering = true
			map.update_fog(player, actors)
			map.map_updated.emit()
			await get_tree().create_timer(flicker_duration).timeout
			GameState.is_flickering = false
			if GameState.light_durability <= 0:
				GameState.glow_slot = false
			map.update_fog(player, actors)
			map.map_updated.emit()


func is_high_score():
	if GameState.high_scores.size() < 10:
		return true
	var lowest_score = GameState.high_scores[-1]["score"]
	if GameState.score > lowest_score:
		return true
	return false


func fade_to_black():
	transitioning = true
	var tween = create_tween()
	var fade_color = DesignSystem.COLOR_NEAR_BLACK
	fade_color.a = 1.0
	tween.tween_property(hud.get_node("FadeOverlay"), "modulate", fade_color, map.level_transition)
	await tween.finished


func fade_from_black():
	var tween = create_tween()
	var fadein = map.level_transition * 0.3
	var fade_color = DesignSystem.COLOR_NEAR_BLACK
	fade_color.a = 1.0
	hud.get_node("FadeOverlay").modulate = fade_color
	fade_color.a = 0.0
	tween.tween_property(hud.get_node("FadeOverlay"), "modulate", fade_color, fadein)
	await tween.finished
	hud.get_node("FadeOverlay").modulate = fade_color
	transitioning = false


func examine_tile():
	var player_pos = Vector2(player.x, player.y)
	var tile_type = map.map_data[player_pos.y][player_pos.x]
	var pretext = "Examined item:"
	var message = "There is nothing to examine here."
	
	if hud.get_node("ExaminePanel").visible:
		hud.get_node("ExaminePanel").hide()
		return
	
	if tile_type in map.examinable_tiles:
		var message_to_display = ""
		if tile_type == GlobalEnums.TileType.HP_UP:
			pretext = "According to the spacesuit data...\n\n"
			var lore_text = GameState.item_lore.get(player_pos, "The scout's corpse is too mangled to examine.")
			message_to_display = pretext + lore_text
			if GameState.corpse_has_crystal.has(player_pos) and not GameState.looted_corpses.has(player_pos):
				GameState.crystal_inventory.append(randi_range(GameState.DEFAULT_LIGHT_DURABILITY * 0.8, GameState.DEFAULT_LIGHT_DURABILITY * 1.4))
				GameState.emit_signal("inventory_changed")
				GameState.looted_corpses[player_pos] = true
				message_to_display += "\n\nYou find a [b][color=" + DesignSystem.COLOR_ACCENT.to_html(false) + "]crystal![/color][/b]"
		if tile_type == GlobalEnums.TileType.CORPSE:
			pretext = "You examine the corpse...\n\n"
			var lore_text = GameState.item_lore.get(player_pos, "The corpse is too mangled to examine.")
			message_to_display = pretext + lore_text
		hud.get_node("ExaminePanel/VBoxContainer/ExamineText").text = message_to_display
		hud.get_node("ExaminePanel").show()
	else:
		hud.log_message("There is nothing to examine here.", DesignSystem.COLOR_TEXT_SECONDARY)


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
	hud.log_message("--- GAME OVER ---")
	hud.log_message("Press [R] to restart")


func _on_quit_to_menu_requested():
	game_is_paused = false
	get_tree().paused = false
	GameState.reset()
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")


func _on_inventory_changed():
	map.update_fog(player, actors)
	map.map_updated.emit()
