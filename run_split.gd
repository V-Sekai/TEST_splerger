@tool
extends EditorScript

const sperlger_const = preload("res://addons/splerger/split_splerger.gd")


# Called when the node enters the scene tree for the first time.
func _run():
	var root: Node = get_editor_interface().get_edited_scene_root()
	sperlger_const.traverse_root_and_split(root)
