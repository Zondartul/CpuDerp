extends Node
class_name Task
var user_name:String;			 # display name
var work_units_total:int = 0: # used for progress bars
	set(val): work_units_total = val; _ping();    
var work_units_complete:int = 0:
	set(val): work_units_complete = val; _ping();
var done = false:
	set(val): 
		if(val): work_units_complete = work_units_total;
		done = val; _ping();
var happy_path = true: # if not happy_path, proceed to exit asap
	set(val): happy_path = val; _ping();
var sub_tasks:Array[Task] = [];
var parent:Task;
var context = null;	# user data for this task
var errors = [];	# errors collected during execution
var print_proxy = null;

func _ping(): # tell parent that something changed
	if parent: parent._pong();

func _pong():
	if parent: _ping();
	#else: tprint(get_progress_tree(0));

func get_progress_tree(indent:int):
	var text = " ".repeat(indent);
	if indent > 0: text += "└";
	text += get_progress_string() + "\n";
	for ch in sub_tasks:
		text += ch.get_progress_tree(indent+1);
	return text;
	
func fail(): happy_path = false;
func mark_done(): done = true;

func add_subtask(task_name):
	var task = Task.new();
	task.parent = self;
	if task_name: task.user_name = task_name;
	sub_tasks.append(task);
	return task;

func get_done_ratio():
	var n_total:float = work_units_total;
	var n_complete:float = work_units_complete;
	for task in sub_tasks:
		n_total += 1;
		n_complete += task.get_done_ratio()[2];
	var ratio = 0;
	if n_total > 0: ratio = n_complete / n_total;
	return [n_total, n_complete, ratio];

func get_progress_string():
	var ratio = get_done_ratio();
	var n_total = ratio[0];
	var n_complete = ratio[1]; 
	var percentage = 100.0*n_complete / float(n_total);
	if is_nan(percentage): percentage = 0.0;
	return "Task %s: %d%% (%d / %d)" % [user_name, percentage, n_complete, n_total];

func tprint(msg):
	if print_proxy:
		if "print" in print_proxy:
			print_proxy.call_deferred("print", msg);
		elif print_proxy is Callable:
			call_deferred("print_proxy", msg);
	elif parent:
		parent.tprint(msg);
	else:
		call_deferred("_defer_print", msg);

func _defer_print(msg):
	print(msg);
