extends Control
## sort of like on observer

## one of these days they'll let you globally
## set the default bus to not master
#@export var toggle_sfx:Button;
@export var toggle_bgm:Button;

#var sfx_on:bool=true;
var bgm_on:bool=true:
	set(val):
		var changed:= bgm_on != val;
		if changed:
			bgm_on = val;
			set_bgm_muted();

func _ready()->void:
	if AudioServer.is_bus_mute(1):
		_on_toggle_music_pressed();




func _on_toggle_music_pressed() -> void:
	bgm_on = not bgm_on

func set_bgm_muted()->void:
	AudioServer.set_bus_mute(1, not bgm_on);
	refresh_toggle_btn(toggle_bgm, bgm_on)
func refresh_toggle_btn(btn:Button, enabled:bool)->void:
	if enabled:
		btn.modulate.v = 1;
		btn.get_node("disabled").hide()
	else:
		btn.modulate.v = .7;
		btn.get_node("disabled").show()


func _on_visibility_changed() -> void:
	bgm_on = not AudioServer.is_bus_mute(1)
