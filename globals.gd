extends Node

## Creates an independent copy of the value
func duplicate_val(obj)->Variant:
	if (obj is Object):
		if "duplicate" in obj:
			return obj.duplicate();
	return obj;

## Creates a deep copy of an object by duplicating each property
func duplicate_deep(src, dest)->void:
	for key in src.get_property_list():
		var old_val = src.get(key.name);
		var new_val = duplicate_val(old_val);
		dest.set(key.name, new_val);
## creats a shallow copy of an object by duplicating each property
func duplicate_shallow(src, dest)->void:
	for key in src.get_property_list():
		dest.set(key.name, src.get(key.name));

#-------- Comparison logic ---------------
func has(obj):
	if obj is Array:
		return not obj.is_empty();
	if obj is Dictionary:
		return not obj.is_empty();
	if obj and (obj is Object) and ("to_bool" in obj):
		return obj.to_bool();
	return not not obj;
