extends Control
class_name UIRoot

@export var ui_sfx:UISFX;



func _ready() -> void:
	recursive_connect_feedback(self);



func recursive_connect_feedback(target:Node)->void:
	_connect_feedback(target)
	for c:Node in target.get_children():
		recursive_connect_feedback(c)
		
func _connect_feedback(target:Node)->void:
	if target is Button:
		target.pressed.connect(ui_sfx.click_sfx);
		target.pressed.connect(press_grow.bind(target));
		
		target.mouse_entered.connect(ui_sfx.hover_sfx)
		target.mouse_entered.connect(mouseover_shake.bind(target));



static func press_grow(target:Control, intensity:float=1.2)->Tween:
	var offset_enabled_before:bool=target.offset_transform_enabled;
	target.offset_transform_enabled = true;
	var tween:=target.create_tween()
	tween.tween_property(target, "offset_transform_scale", Vector2(intensity, intensity), .1)
	tween.tween_property(target, "offset_transform_scale", Vector2.ONE, .1)
	tween.tween_callback(target.set_offset_transform_enabled.bind(offset_enabled_before))
	return tween

static func mouseover_shake(target:Control, srr:float = PI/32, cycle:float = .05, target_scale:Vector2=Vector2(1.05, 1.05))->Tween:
	var offset_enabled_before:bool = target.offset_transform_enabled;
	target.offset_transform_enabled = true;
	if "disabled" in target and target.disabled:
		srr/= 8;
		target_scale = Vector2.ONE
	if target.size.x > 100:
		srr /= 4

	var tween:Tween = target.create_tween();
	tween.tween_property(target, "offset_transform_rotation", srr, cycle);
	tween.parallel().tween_property(target, "offset_transform_scale", target_scale, cycle)
	tween.tween_property(target, "offset_transform_rotation", -srr, cycle);
	
	
	tween.tween_property(target, "offset_transform_rotation", 0, cycle);
	tween.parallel().tween_property(target, "offset_transform_scale", Vector2.ONE, cycle)
	tween.tween_callback(target.set_offset_transform_enabled.bind(offset_enabled_before));
	
	return tween

static func fade_in(target:CanvasItem, duration:float = .5, and_show:bool=true)->Tween:
	if and_show: target.show();
	
	target.modulate.a = .1
	## tween goes into the control because of nodes that process when pasued
	var tween:Tween = target.create_tween();
	tween.tween_property(target, "modulate:a", 1, duration);
	return tween
	

static func fade_out(target:CanvasItem, duration:float = .5, hide_after:bool=true)->Tween:
	var tween:Tween = target.create_tween();
	tween.tween_property(target,"modulate:a", 0, duration);
	if hide_after:
		tween.tween_callback(target.hide);
		return tween;
	else:
		return tween;
