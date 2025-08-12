extends Node2D

func _process(delta):
	# Tell the node to redraw itself on every frame.
	queue_redraw()


func _draw():
	# Get a reference to the main game scene to access its variables.
	var main_node = get_node("/root/Main")
	if not main_node or not main_node.map_data:
		return # Don't draw if the main game isn't ready yet.

	# Define the size of each tile on the mini-map.
	var mini_tile_size = 2

	# Loop through the entire map grid.
	for y in range(main_node.map_data.size()):
		for x in range(main_node.map_data[y].size()):
			var fog_state = main_node.fog_map[y][x]
			
			# Only draw tiles that are "known" (1) or "visible" (2).
			if fog_state > 0:
				var tile_type = main_node.map_data[y][x]
				var tile_color

				if tile_type == 1: # Wall
					tile_color = Color(0.4, 0.4, 0.4) # Dim white
				elif tile_type == 2: # Stairs
					tile_color = Color.MAGENTA
				elif tile_type == 5: # Potion
					tile_color = Color.DARK_ORANGE
				elif tile_type == 6: # HP-Up
					tile_color = Color.DARK_ORANGE
				elif tile_type == 7: # Flashlight
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
