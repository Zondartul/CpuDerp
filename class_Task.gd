extends Node
class_name Task
var user_name:String;			 # display name
var work_units_total:int = 0: # used for progress bars
	set(val): work_units_total = val; _ping();    
var work_units_complete:int = 0:
	set(val): work_units_complete = val; _ping();
var done:bool = false:
	set(val): 
		if(val): work_units_complete = work_units_total;
		done = val; _ping();
var happy_path:bool = true: # if not happy_path, proceed to exit asap
	set(val): happy_path = val; _ping();
var sub_tasks:Array[Task] = [];
var parent:Task;
var context:Variant = null;	# user data for this task
var errors:Array = [];	# errors collected during execution
var print_proxy:Variant = null;

func _ping(): # tell parent that something changed
	if parent: parent._pong();

func _pong():
	if parent: _ping();
	#else: tprint(get_progress_tree(0));

func get_progress_tree(indent:int)->String:
	var text:String = " ".repeat(indent);
	if indent > 0: text += "└";
	text += get_progress_string() + "\n";
	for ch in sub_tasks:
		text += ch.get_progress_tree(indent+1);
	return text;

func get_full_name()->String:
	var S:String = "";
	if parent: S += parent.get_full_name() + ".";
	S += user_name;
	return S;
	
func fail()->void: 
	happy_path = false;
	var stack:Array[Dictionary] = get_stack();
	call_deferred("defer_print_stack", stack);

func defer_print_stack(arg):
	var S:String = "Task %s failed at:\n" % get_full_name();
	var indent:String = " ";
	arg.reverse();
	for item in arg:
		S += "%s%s.%s: line %d\n" % [indent, item.source,item.function,item.line];
		indent += " ";
	S += "\n"
	print(S);

func mark_done()->void: done = true;

func add_subtask(task_name)->Task:
	var task:Task = Task.new();
	task.parent = self;
	if task_name: task.user_name = task_name;
	sub_tasks.append(task);
	return task;

func get_done_ratio()->Array:
	var n_total:float = work_units_total;
	var n_complete:float = work_units_complete;
	for task in sub_tasks:
		n_total += 1;
		n_complete += task.get_done_ratio()[2];
	var ratio:float = 0;
	if n_total > 0: ratio = n_complete / n_total;
	return [n_total, n_complete, ratio];

func get_progress_string()->String:
	var ratio:Array = get_done_ratio();
	var n_total:float = ratio[0];
	var n_complete:float = ratio[1]; 
	var percentage:float = 100.0*n_complete / float(n_total);
	if is_nan(percentage): percentage = 0.0;
	return "Task %s: %d%% (%d / %d)" % [user_name, percentage, n_complete, n_total];

func tprint(msg)->void:
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
