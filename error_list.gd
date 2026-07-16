extends Node

# assembler errors
const ERR_01 = "Error 01: Error_reporter: unknown context";
const ERR_02 = "Error 02: Unlinked references remain (count %d)";
const ERR_03 = "Error 03: patch_ref: reference not marked in shadows";
const ERR_04 = "Error 04: can only have one immediate/offset value per command";
const ERR_05 = "Error 05: unrecognized DB item";
const ERR_06 = "Error 06: unknown DB item";
const ERR_07 = "Error 07: Invalid op [%s]";
const ERR_08 = "Error 08: Can't have offset on top of immediate";
const ERR_09 = "Error 09: Can't have array access on top of immediate";
const ERR_10 = "Error 10: can't emit value, doesn't fit in byte: [%s]";
const ERR_11 = "Error 11: can't emit value, doesn't fit in u32: [%s]";
const ERR_12 = "Error 12: unexpected input";
const ERR_13 = "Error 13: Unlinked reference to [%s]";
const ERR_14 = "Error 14: Can't have dereference on top of array access";

# analyzer errors
const ERR_21 = "Error 21: Not implemented";
const ERR_22 = "Error 22: analyze_expr: unimplemented expr type: [%s]";
const ERR_23 = "Error 23: analyze: not implemented for class [%s]";
const ERR_24 = "Error 24: analyze: expr op not implemented: [%s]";
const ERR_25 = "Error 25: analyze: expr op not implemented: [%s]";
const ERR_26 = "Error 26: analyzer: func_call: unexpected expr class";
const ERR_27 = "Error 27: analyze: broken if-else block";
const ERR_28 = "Error 28: analyzer: func_def: unexpected expr class";
const ERR_29 = "Error 29: Identifier not found: [%s]";
const ERR_30 = "Error 30: 'Continue' statement outside of a loop";
const ERR_31 = "Error 31: Operator '%s' is not allowed here.";
const ERR_32 = "Error 32: Variable declaration can't have [%s] as left-hand-side of assignment";
const ERR_43 = "Error 33: Invalid character literal: [%s]";
const ERR_44 = "Error 34: #include syntax error";
const ERR_45 = "Error 35: #include file not found: [%s]";
const ERR_46 = "Error 36: function [%s] expected %d arguments, got %d";
const ERR_47 = "Error 37: function [%s] previously declared with %d arguments, now redeclared with %d arguments";
const ERR_48 = "Error 38: analyzer: array literal: unexpected expr class";
const ERR_53 = "Error 33: Can't assign value of type [%s] to variable of type [%s]";
const ERR_54 = "Error 34: analyze_type_expr: unimplemented ast type: [%s]";
const ERR_55 = "Error 35: Can't do operator %s between %s and %s";
const ERR_56 = "Error 36: Operator %s is not an infix op";
const ERR_57 = "Error 37: Operator %s is not a postfix op";
const ERR_58 = "Error 38: Array index must be one of integer types (got %s)";
const ERR_59 = "Error 39: Type %s cannot be dereferenced";
