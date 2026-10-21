extends AudioStreamPlayer
class_name UISFX

@export var hover:AudioStream;
@export var click:AudioStream;

func hover_sfx()->void:
	stream = hover;
	play()

func click_sfx()->void:
	stream = click;
	play();
