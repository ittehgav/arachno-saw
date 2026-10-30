extends Node
class_name RunControl;

## RUN CONTROL

## controls the run score,
## bridges run with eventual global state
## replay system?
## track amount of bugs and whatnot
## records anything that matters about the run when the scene disappears


## instantiated in any playable scene to connect signals via editor
## ALL SIGNALS CONNECTIONS WILL BE TO GD CONVENTION
## default _on_signal function names

## can get slotted in/out with a copy on the singleton

## score
## will react mostly to signals and update the run score

signal run_started;
signal finished(won:bool)

## score system
@export var progress_timers:Array[Timer]
signal score_changed;
var player_name:String="Player";
var score:float:
	set(val):
		if val != score:
			score = val;
			score_changed.emit()

@export var score_ticker:Timer;

var placeholder:=true;

## ALL SCORE SOURCES:
## time - score_time_ticker timeout will add 1(?) point

## boards dropped - smaller the board is after the drop, the more 
## points these yield

## fly consumed - 
## buff flies give a default value
## score fly gives double what other buffs do
## skull fly (when shielded) gives 5x
## combo bar type shit for getting flies


func start_run()->void:
	## WILL COMPUTE ALL RUNS IN A GIVEN GAME WINDOW IN THE SAME INSTANCEa
	current_fly_combo = 0;
	setup_signals()
	_last_start_time = Time.get_ticks_msec()
	set_progress_timers(true)
	_reset_counters();
	run_started.emit();

@onready var initial_score_ticker_wait_time:float=score_ticker.wait_time;
func _reset_counters()->void:
	score = 0;
	flies_consumed = {
		ft.speed:0,
		ft.shield:0,
		ft.teleport:0,
		ft.coin:0,
		ft.death:0
	}
	score_ticker.wait_time = initial_score_ticker_wait_time;
	score_multiplier = 1;
	
func setup_signals()->void:
	GLB.spider.fly_consumed.connect(_on_fly_consumed)
	GLB.board_container.board_dropped.connect(_on_board_dropped)

func finish_run(won:bool)->void:
	set_progress_timers(false)
	finished.emit(won)
	HighScores.register_run();


func set_progress_timers(start:bool)->void:
	if start:
		for t:Timer in progress_timers:
			t.start();
	else:
		for t:Timer in progress_timers:
			t.stop()

@export var fly_combo_timeout:Timer;


var boards_dropped:int;

const bsm = 5 ## base stage multiplier
func _on_board_dropped(_b:StaticBody3D)->void:
	var gain:float= ((1 + current_fly_combo * .1) * (GLB.board_container.current_stage + 2)) ** 3;
	score += gain
	
	
	


signal fly_combo_started;
signal fly_combo_incremented(fly:ft);
signal fly_combo_ended;
var current_fly_combo:int=0;
var combo_multiplier:float:
	get():
		return 1.0 + current_fly_combo/10.0


func _on_fly_consumed(fly:Fly)->void:
	if current_fly_combo == 0:
		fly_combo_started.emit();
	flies_consumed[fly.type] += 1;
	
	current_fly_combo += 1;
	fly_combo_timeout.start()
	fly_combo_incremented.emit(fly.type)
	
	score += fly_score_values[fly.type] * combo_multiplier;
	
func _on_fly_combo_timeout() -> void:
	fly_combo_ended.emit();
	current_fly_combo = 0;
	
const ft = Fly.Type
var flies_consumed:Dictionary[ft, int] = {
	ft.speed:0,
	ft.shield:0,
	ft.teleport:0,
	ft.coin:0,
	ft.death:0
}
const fly_score_values:Dictionary[ft, float] = {
	## its floats so it's simpler to multiply
	ft.speed:1.0,
	ft.shield:1.0,
	ft.teleport:1.0,
	
	ft.coin:3.0,
	
	## because you can only really catch this with shield
	ft.death:5.0
}
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_on_paused();
	elif what == NOTIFICATION_UNPAUSED:
		_on_unpaused()

var score_multiplier:float = 1.0;
func _on_score_time_ticker_timeout() -> void:
	score += 1 * score_multiplier;


func _on_accelerate_timeout() -> void:
	GLB.board_path_follow.accel *= 1.05
	score_ticker.wait_time /= 1.05
	GLB.spider.SPEED *= 1.05
	score_multiplier *= 1.05
	

## time tracking
var _elapsed_time: float = 0.0
var _last_start_time: int = 0
var _paused := false

func get_elapsed_time() -> float:
	if _paused:
		return _elapsed_time
	return _elapsed_time + (Time.get_ticks_msec() - _last_start_time) / 1000.0

func _on_paused() -> void:
	if _paused:
		return
	_elapsed_time += (Time.get_ticks_msec() - _last_start_time) / 1000.0
	_paused = true
func _on_unpaused() -> void:
	if not _paused:
		return
	_last_start_time = Time.get_ticks_msec()
	_paused = false
