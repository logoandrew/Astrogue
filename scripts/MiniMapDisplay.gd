extends Node2D

var font = preload("res://assets/fonts/SpaceMono-Regular.ttf")
var mini_tile_size = 2
var hp_to_break_map = 5
var main_node
var frame_counter = 0

func _ready():
	main_node = get_node("/root/Main")
	if main_node:
		main_node.map_updated.connect(queue_redraw)


func _process(delta):
	frame_counter += 1
	if main_node and main_node.player and main_node.player["hp"] <= hp_to_break_map:
		if frame_counter % 15 == 0:
			queue_redraw()


func _draw():
	if not main_node or not main_node.map_data or not main_node.player:
		return # Don't draw if the main game isn't ready yet.

	# Broken minimap
	var broken_map_hp = randf_range(hp_to_break_map - 0.5, hp_to_break_map + 0.05)
	if main_node.player["hp"] <= broken_map_hp:
		var time = Time.get_ticks_msec()
		if time % 2000 < 1000:
			var text = "OFF-LINE"
			var font_size = 10
			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var center_pos = get_parent().size / 2
			var text_pos = center_pos - (text_size / 2)
			text_pos.y += 9
			draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.RED)
		return
	
	# Loop through the entire map grid.
	for y in range(main_node.map_data.size()):
		for x in range(main_node.map_data[y].size()):
			var fog_state = main_node.fog_map[y][x]
			
			# Only draw tiles that are "known" or "visible".
			if fog_state == GlobalEnums.FogState.KNOWN or fog_state == GlobalEnums.FogState.VISIBLE:
				var tile_type = main_node.map_data[y][x]
				var tile_color

				if tile_type == GlobalEnums.TileType.WALL:
					tile_color = Color(0.4, 0.4, 0.4) # Dim white
				elif tile_type == GlobalEnums.TileType.STAIRS:
					tile_color = Color.MAGENTA
				elif tile_type == GlobalEnums.TileType.HEALTH or tile_type == GlobalEnums.TileType.HP_UP or tile_type == GlobalEnums.TileType.LIGHT:
					tile_color = Color.DARK_ORANGE
				else: # Floor
					tile_color = Color(0.25, 0.25, 0.25) # Dim gray

				var rect = Rect2(x * mini_tile_size, y * mini_tile_size, mini_tile_size, mini_tile_size)
				draw_rect(rect, tile_color)
	
	if main_node.player:
		var player_x = main_node.player["x"]
		var player_y = main_node.player["y"]
		var player_color = Color.LAWN_GREEN
		var rect = Rect2(player_x * mini_tile_size, player_y * mini_tile_size, mini_tile_size, mini_tile_size)
		draw_rect(rect, player_color)
