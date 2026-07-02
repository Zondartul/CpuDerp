extends Node
var tasks = [];

func start(foo:Callable):
	var task = Task.new();
	var thread = Thread.new();
	thread.start(foo.bind(task));
	tasks.append({"task":task, "thread":thread});
	return task;
