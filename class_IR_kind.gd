extends Node
class_name IRKind

var code_blocks:Dictionary[String,CodeBlock]
var scopes:Dictionary[String,Scope]
var all_syms:Dictionary[String,IR_Value] = {};
