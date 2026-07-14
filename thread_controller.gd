extends Node
var tasks:Dictionary[Task,Thread] = {};

func get_first_task()->Task:
	if tasks.keys().size():
		return tasks.keys()[0];
	return null;

func start(foo:Callable)->Task:
	var task:Task = Task.new();
	var thread:Thread = Thread.new();
	thread.start(foo.bind(task));
	tasks[task] = thread;
	#tasks.append({"task":task, "thread":thread});
	return task;

func end(task:Task)->Variant:
	assert(task in tasks);
	var thread:Thread = tasks[task];
	tasks.erase(task);
	return thread.wait_to_finish();
