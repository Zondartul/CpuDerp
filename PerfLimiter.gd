extends Object
class_name PerfLimiter

var cost:float;
var credit:float;
var max_credit:float;
var enabled:bool;
var cascades_to:Array[PerfLimiter] = [];

func _init(period:float, new_max_credit=null):
	cost = period;
	credit = 0.0;
	enabled = true;
	if new_max_credit == null:
		max_credit = cost;
	else:
		max_credit = float(new_max_credit);

func add_credit(delta:float):
	credit += delta;
	if credit > max_credit: credit = max_credit;

func should_run():
	return credit >= cost;

func cascade():
	for other_limiter:PerfLimiter in cascades_to:
		other_limiter.prime()

func prime():
		credit = max(credit, cost);

func run(delta:float):
	add_credit(delta);
	if not enabled: return false;
	if should_run():
		credit -= cost;
		cascade();
		return true;
	return false;

# EXAMPLE USAGE
#var perf = {
	#"all":PerfLimiter.new(1.0),
	#"regs":PerfLimiter.new(0.1),
	#"stack":PerfLimiter.new(0.1),
	#"ip":PerfLimiter.new(0.5),
	#"pointers":PerfLimiter.new(0.1),
	#"locals":PerfLimiter.new(1.0)
	#};
#perf.all.triggers_others = [perf.regs, perf.stack, perf.ip, perf.pointers, perf.locals];
#
#func set_enabled_perfs(enable_list:Array[String]):
	#for cateogry in perf:
		#perf[category].enabled = bool(category in enable_list);
#
#var perf_always_run = ["all", "regs", "stack", "ip"];
#var perf_enabled_by_default = ["all", "regs", "stack", "ip"];
#
#func _ready():
	#set_enabled_perfs(perf_enabled_by_default);
#
#func _process(delta):
	#perf.all.run(delta);
	#if perf.regs.run(delta):
		#update_registers();
	#if perf.stack.run(delta):
		#update_stack();
#
#func _on_frame_change():
	#perf.stack.prime()
#
#func _on_GUI_tab_change(new_tab):
	#set_enabled_perfs(perf_always_run);
	#if new_tab in perf_for_tabs:
		#perf[perf_for_tabs[new_tab]].enabled = true;
