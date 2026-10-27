extends Control

@export var movement_instructions:VBoxContainer;
@export var dont_die_instruction:Label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	await GLB.board_container.saw_touched;
	UIRoot.fade_out(movement_instructions);
	var t:= UIRoot.fade_in(dont_die_instruction)
	var fs:int = dont_die_instruction.get_theme_font_size("font_size");
	t.parallel().tween_property(dont_die_instruction, "theme_override_font_sizes/font_size", fs * 1.25, .2 )
	t.parallel().tween_property(dont_die_instruction, "theme_override_font_sizes/font_size", fs, 1 )
	await t.finished;
	UIRoot.fade_out(dont_die_instruction, 10)
	
