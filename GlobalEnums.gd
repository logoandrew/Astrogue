# GlobalEnums.gd
extends Node

# This script holds enums that need to be accessed globally.
# Because it's an Autoload, any other script can access its contents
# using the name defined in the Project Settings (e.g., GlobalEnums.TileType).
enum TileType { FLOOR, WALL, STAIRS, POTION, HP_UP, FLASHLIGHT }
