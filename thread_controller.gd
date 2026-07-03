extends Node
var tasks = {};

func get_first_task():
	if tasks.keys().size():
		return tasks.keys()[0];
	return null;

func start(foo:Callable):
	var task = Task.new();
	var thread = Thread.new();
	thread.start(foo.bind(task));
	tasks[task] = thread;
	#tasks.append({"task":task, "thread":thread});
	return task;

func end(task:Task):
	assert(task in tasks);
	var thread = tasks[task];
	tasks.erase(task);
	return thread.wait_to_finish();
