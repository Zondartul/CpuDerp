extends Node

# Todo
# [bug] ctrl-s doesn't save
# [bug] build doesn't save
# [bug] opening another file and then tabbing back makes it not compile
#
# [refactor] split assembler into low-lvl and high-lvl
# [idea] paste file into memory or load from memory and save to disk
#
# [enhancement] Editor should indicate when <build> succeeds.
# [enhancement] Debugger should update continuously while CPU is running
# [bug] CPU IP doesn't change when running (or calling?)
# [feature] Debugger should show current assembly instruction
#           - from debug symbols        
#			- also from decompiled
# [feature] Debugger should show current function
#			- from debug symbols
#			- from stack trace
# [automation] for debug, set a list of UI interactions 
#			that should happen automatically when starting
# [enhancement] infer language from file extension
# [bug] I suspect that multiple array access has a landmine as it produces a needs_deref value
# [bug] sometimes the wrong tab gets the filename*
# [bug] compiler and codegen do not clear data between runs
# [enchancement] analyzer should check argument count
# [enhancement] compiling should also reset CPU and screen
# [enhancement] compiling should clear the console
#
