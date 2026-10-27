extends Node
class_name HighScoreControl;

signal highscores_loaded;
signal highscores_changed;

const save_path:="user://scoreboard.save"

var current_high_scores:Array[Dictionary];
var highest_score:int;

class ScoreEntry:
	func _init(n:String, s:int) -> void:
		score = s;
		name = n;
	var name:String;
	var score:int;


#
func _ready() -> void:
	load_scoreboard()
	

func load_scoreboard()->void:
	var sb:Variant= FileAccess.open(save_path, FileAccess.READ).get_var();
	if sb != null and sb != {}:
		current_high_scores = sb.high_scores
		current_high_scores.sort_custom(func(a:Dictionary, b:Dictionary)->bool:return a.score > b.score);
		highest_score = current_high_scores[0].score;
		
		highscores_loaded.emit()

func clear_record()->void:
	highest_score = 0;
	var board := {};
	var fa:=FileAccess.open(save_path, FileAccess.WRITE);
	fa.store_var(board);
	fa.close();
	highscores_changed.emit()

func save_scoreboard(last_saved_name:String)->void:
	## just always save everything its fine
	var fa:= FileAccess.open(save_path, FileAccess.WRITE);
	var board:= {
		"last_saved_name":last_saved_name,
		"high_scores":current_high_scores
	}
	fa.store_var(board)
	fa.close()

func register_score(e:ScoreEntry)->void:
	current_high_scores.append({"name":e.name, "score":e.score});
	current_high_scores.sort_custom(func(a:Dictionary, b:Dictionary)->bool:return a.score > b.score)
	save_scoreboard(e.name);
	if e.score > highest_score:
		highest_score = e.score;
	
	highscores_changed.emit()



func register_run()->void:
	## just catch from run singleton no dramar
	var score:int = int(Run.score);
	var pname:String = Run.player_name
	var entry:ScoreEntry = ScoreEntry.new(pname, score);
	register_score(entry);
