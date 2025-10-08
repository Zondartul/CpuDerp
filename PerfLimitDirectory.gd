extends Object
class_name PerfLimitDirectory

const class_PerfLimiter = preload("res://PerfLimiter.gd");
var perfs:Dictionary = {};

func _init(new_perfs=null):
	if new_perfs:
		for perf_name in new_perfs:
			var perf_freq = new_perfs[perf_name];
			perfs[perf_name] = PerfLimiter.new(perf_freq);
		if "all" in perfs:
			for perf_name in perfs:
				if perf_name == "all": continue;
				perfs.all.cascades_to.append(perfs[perf_name]);

func set_enabled_perfs(enable_list:Array[String]):
	for perf_name in perfs:
		perfs[perf_name].enabled = (perf_name in enable_list);

func credit_all(delta:float):
	for perf_name in perfs:
		perfs[perf_name].add_credit(delta);

func _get(key: StringName):
	return perfs.get(key)

func _set(key: StringName, value: Variant) -> bool:
	perfs[key] = value
	return true
