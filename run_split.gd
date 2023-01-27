extends Node3D

const sperlger_const = preload("res://addons/splerger/split_splerger.gd")

# Called when the node enters the scene tree for the first time.
func _ready():
	sperlger_const.traverse_root_and_split(self)


