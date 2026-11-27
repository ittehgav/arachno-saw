extends Node

const code: String = "dtdtdtdtdtdtdt"
@onready var sfx:AudioStream = load("res://assets/sound/ui/click.ogg")

var _typed: String = ""

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var character :String= event.as_text_key_label().to_lower()

		# Ignore non-letter keys
		if character.length() != 1 or not character.unicode_at(0) in range("a".unicode_at(0), "z".unicode_at(0) + 1):
			return

		_typed += character

		# Keep the buffer no longer than the code
		if _typed.length() > code.length():
			_typed = _typed.substr(_typed.length() - code.length())

		if _typed == code.to_lower():
			_typed = ""
			_on_code_entered()

func _on_code_entered() -> void:
	var player:AudioStreamPlayer=AudioStreamPlayer.new();
	player.stream = sfx;
	player.volume_db = 20
	player.autoplay = true;
	player.finished.connect(_enable_dev_tools);
	player.finished.connect(player.queue_free)
	Run.add_child(player)

func _enable_dev_tools()->void:
	var dt:= DevTools.new();
	Run.add_child(dt);
	
