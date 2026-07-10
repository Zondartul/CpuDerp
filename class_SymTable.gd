extends Node
class_name SymTable

var global:IR_func; # the global scope
var funcs:Dictionary[String, IR_func];
