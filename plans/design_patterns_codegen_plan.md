# Design Patterns (GoF OOP) Codegen Plan

**Persona**: Gang of Four Design Patterns Advocate  
**Date**: 2026-06-27  
**Context**: Replace the ad-hoc [`codegen_md.gd`](../scenes/codegen_md.gd) (833 lines) with a data-driven, loosely coupled design using classic GoF patterns.

---

## 1. Diagnosis of the Current Codegen (GoF View)

The existing [`codegen_md.gd`](../scenes/codegen_md.gd) violates nearly every GoF principle:

| Violation | Location | GoF Critique |
|-----------|----------|--------------|
| **Giant switch statement** | [`generate_cmd()`](../scenes/codegen_md.gd:266) | A `match` on 12 IR opcodes violates the **Open-Closed Principle**. Adding a new opcode requires modifying this switch AND adding a new `generate_cmd_*` method. The varying aspect (opcode→codegen logic) is not encapsulated. |
| **Hardcoded templates in source** | [`op_map`](../scenes/codegen_md.gd:12) | Assembly templates are string constants embedded in code. Changes to the ISA require recompilation. Violates "program to an interface, not an implementation" — the template IS the implementation. |
| **String-based symbol references** | [`emit()`](../scenes/codegen_md.gd:474) | All operands are resolved at emit time by scanning template strings for `$`, `@`, `^` markers. This is runtime string parsing where a **Strategy** or **Visitor** pattern would give compile-time safety and clarity. |
| **Mutable global state** | `all_syms`, `regs_in_use`, `cur_assy_block`, `cur_block`, `cb_stack`, `entered_scopes` | 7+ mutable state variables threaded through the module. Violates encapsulation. State should be owned by collaborating objects with well-defined responsibilities. |
| **Mixed responsibilities** | `generate()` / `deserialize()` / `emit_cb()` / `allocate_vars()` | The same class parses YAML, allocates storage, resolves registers, expands templates, emits assembly, AND tracks debug locations. **Low cohesion**. |
| **No interface abstraction** | All methods on `Node` | There are no abstract interfaces for "code generator", "template provider", "register allocator", or "operand resolver". Everything is coupled to concrete implementations. |
| **Procedural, not object-oriented** | Most methods are `func name(input)->output` | The codebase reads like a procedural script, not an OOP design. Objects like `AssyBlock`, `CodeBlock`, `IR_Cmd` exist but are passive data holders, not active participants. |

**Root cause**: The codegen is a **monolithic procedural module** dressed in Godot's Node clothing. There is no encapsulation, no polymorphism, no composition, and no separation of concerns.

---

## 2. GoF Design Principles Applied

### 2.1 Program to an Interface, Not an Implementation

Every component depends on abstract interfaces, not concrete classes. This enables swapping implementations (e.g., different register allocators, different template backends) without modifying consumers.

### 2.2 Favor Composition Over Inheritance

The codegen is assembled from collaborating objects, not a deep class hierarchy. The `CodeGenerator` **has-a** `TemplateRegistry`, **has-a** `RegisterAllocator`, **has-a** `StorageAllocator`, **has-a** `OperandResolver` — it is not a subclass of any of these.

### 2.3 Identify the Varying Aspects and Encapsulate Them

| Varying Aspect | Encapsulation | GoF Pattern |
|----------------|--------------|-------------|
| Opcode→Assembly mapping | `TemplateRegistry` with `Template` objects | **Strategy** |
| Register assignment | `RegisterAllocator` interface | **Strategy** |
| Storage allocation | `StorageAllocator` interface | **Strategy** |
| Operand resolution | `OperandResolver` interface | **Chain of Responsibility** |
| IR command dispatch | `IrCommandVisitor` | **Visitor** |
| Instruction template structure | `Template` with `Parameter` slots | **Prototype** |
| Assembly block composition | `AssyComposite` as tree | **Composite** |
| Debug/location overlay | `LocationDecorator` wrapping emitters | **Decorator** |

### 2.4 Loose Coupling, High Cohesion

Each class has exactly one reason to change. Classes communicate through interfaces, not shared mutable state. The pipeline is a directed acyclic graph of object collaborations.

---

## 3. GoF Design Patterns Catalog

### Pattern 1: Command Pattern — IR Commands as First-Class Objects

**Intent**: Encapsulate a request as an object, thereby letting you parameterize clients with different requests.

**Current problem**: [`generate_cmd()`](../scenes/codegen_md.gd:266) is a huge match statement. IR commands are flat `StringName` arrays (`cmd.words[0]`), not typed objects.

**Design**:

```
┌──────────────────┐
│   IrCommand      │  (abstract interface)
├──────────────────┤
│ + accept(visitor)│
│ + getOperands()  │
│ + getOpcode()    │
└──────────────────┘
        ▲
        │ implements
        │
┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
│   MovCommand      │ │   OpCommand       │ │   IfCommand       │ │   CallCommand     │
├───────────────────┤ ├───────────────────┤ ├───────────────────┤ ├───────────────────┤
│ + dest: Operand   │ │ + op: String      │ │ + condBlock: ref  │ │ + function: ref   │
│ + src: Operand    │ │ + arg1: Operand   │ │ + result: Operand │ │ + args: Operand[] │
│ + accept(v)       │ │ + arg2: Operand   │ │ + bodyBlock: ref  │ │ + result: Operand │
│                   │ │ + result: Operand │ │ + elseLbl: Label  │ │ + accept(v)       │
│                   │ │ + accept(v)       │ │ + endLbl: Label   │ │                   │
└───────────────────┘ └───────────────────┘ └───────────────────┘ └───────────────────┘
```

**Implementation**:

[`class_IR_Cmd.gd`](../class_IR_cmd.gd) — base interface:
```gdscript
# Abstract base for all IR commands
class_name IrCommand

func get_opcode() -> String:
	push_error("abstract method")
	return ""

func accept(visitor: IrCommandVisitor) -> String:
	push_error("abstract method")
	return ""
```

Concrete commands encapsulate their operands as typed fields, not positional array indices:

[`class_IR_Cmd_Mov.gd`](../class_IR_Cmd_Mov.gd):
```gdscript
class_name IrCmdMov extends IrCommand
var dest: Operand
var src: Operand

func get_opcode() -> String: return "MOV"

func accept(visitor: IrCommandVisitor) -> String:
	return visitor.visit_mov(self)
```

### Pattern 2: Visitor Pattern — IR Command Dispatch

**Intent**: Represent an operation to be performed on the elements of an object structure. Lets you define a new operation without changing the classes of the elements.

**Current problem**: To add a new IR opcode, you must modify [`generate_cmd()`](../scenes/codegen_md.gd:266) AND add a new `generate_cmd_*` method AND update the match. Every codegen variant (e.g., debug mode, optimized mode, different target) needs a parallel set of methods.

**Design**:

```
┌────────────────────────────┐
│   IrCommandVisitor         │  (interface)
├────────────────────────────┤
│ + visit_mov(cmd)           │
│ + visit_op(cmd)            │
│ + visit_if(cmd)            │
│ + visit_else_if(cmd)       │
│ + visit_else(cmd)          │
│ + visit_while(cmd)         │
│ + visit_call(cmd)          │
│ + visit_call_indirect(cmd) │
│ + visit_return(cmd)        │
│ + visit_enter(cmd)         │
│ + visit_leave(cmd)         │
│ + visit_alloc(cmd)         │
│ + visit_mov_arr(cmd)       │
└────────────────────────────┘
        ▲
        │ implements
        │
┌──────────────────────────────────┐
│   AssemblyEmitterVisitor         │  (the codegen itself)
├──────────────────────────────────┤
│ - template_reg: TemplateRegistry │
│ - reg_alloc: RegisterAllocator   │
│ - stor_alloc: StorageAllocator   │
│ - operand_res: OperandResolver   │
├──────────────────────────────────┤
│ + visit_mov(cmd) -> String       │
│ + visit_op(cmd) -> String        │
│ + visit_if(cmd) -> String        │
│ + ...                            │
└──────────────────────────────────┘
```

**Usage**:
```gdscript
var visitor = AssemblyEmitterVisitor.new(
	template_registry, register_allocator, storage_allocator, operand_resolver
)
for cmd in code_block.commands:
	var assembly_text: String = cmd.accept(visitor)
	output.append(assembly_text)
```

**Key benefit**: Adding a new opcode means:
1. Create a new `IrCommand` subclass (e.g., `IrCmdSwitch`)
2. Add `visit_switch(cmd)` to the `IrCommandVisitor` interface
3. Implement it in `AssemblyEmitterVisitor`

No `match` statement to maintain. No modification of existing classes (except the visitor interface). This is the **Open-Closed Principle** in action.

### Pattern 3: Strategy Pattern — Pluggable Algorithms

**Intent**: Define a family of algorithms, encapsulate each one, and make them interchangeable.

**Current problem**: Register allocation is hardcoded as a dictionary flip-flop. Storage allocation is inline. Template matching is a flat `op_map` dictionary. None of these can be replaced or extended.

**Design**:

```
┌──────────────────────────┐
│   RegisterAllocator      │  (abstract strategy)
├──────────────────────────┤
│ + allocate(operand)      │
│ + free(reg)              │
│ + spill_to_stack(reg)    │
└──────────────────────────┘
        ▲
        │
┌─────────────────────┐ ┌─────────────────────┐ ┌──────────────────────┐
│ LinearScanAllocator │ │ GraphColoringAlloc  │ │ NoAllocationStub     │
├─────────────────────┤ ├─────────────────────┤ ├──────────────────────┤
│ - regs: bool[4]     │ │ - interference: Map │ │ (for direct-to-      │
│ - spills: StackSlot │ │ - colors: int[]     │ │  memory targets)     │
└─────────────────────┘ └─────────────────────┘ └──────────────────────┘

┌──────────────────────────┐
│   StorageAllocator       │  (abstract strategy)
├──────────────────────────┤
│ + allocate(var, scope)   │
│ + allocate_temp(scope)   │
└──────────────────────────┘
        ▲
        │
┌─────────────────────┐ ┌─────────────────────┐
│ SimpleStackAlloc    │ │ GlobalSymbolAlloc   │
├─────────────────────┤ ├─────────────────────┤
│ + locals: OffsetMap │ │ + symbols: LabelMap │
│ + args: OffsetMap   │ │                      │
└─────────────────────┘ └──────────────────────┘

┌──────────────────────────┐
│   TemplateProvider       │  (abstract strategy)
├──────────────────────────┤
│ + get_template(opcode)   │
│ + get_all_opcodes()      │
└──────────────────────────┘
        ▲
        │
┌─────────────────────┐ ┌─────────────────────┐
│ YamlTemplateLoader  │ │ InlineTemplateDict  │
├─────────────────────┤ ├─────────────────────┤
│ - data: Dict        │ │ (for backward compat)│
│ - path: String      │ │                      │
└─────────────────────┘ └──────────────────────┘
```

**Usage**:
```gdscript
var reg_alloc: RegisterAllocator
match config.register_allocation_strategy:
	"linear_scan":  reg_alloc = LinearScanAllocator.new()
	"graph_coloring": reg_alloc = GraphColoringAllocator.new()
	"none":         reg_alloc = NoAllocationStub.new()

var emitter = AssemblyEmitterVisitor.new(
	template_reg, reg_alloc, stor_alloc, oper_res
)
```

### Pattern 4: Template Method Pattern — Instruction Generation Skeleton

**Intent**: Define the skeleton of an algorithm in an operation, deferring some steps to subclasses.

**Current problem**: Each `generate_cmd_*` method duplicates the same pattern: mark location, resolve operands, emit text, track write pointer.

**Design**:

```gdscript
class_name InstructionGenerator
extends Reference

# Template Method — defines the skeleton of instruction generation
func generate(cmd: IrCommand) -> GeneratedInstruction:
	var ctx = GenerationContext.new()
	
	# Steps that subclasses CAN override via strategy injection:
	before_generate(cmd, ctx)          # hook: e.g., mark location begin
	expand_template(cmd, ctx)          # core: template → text
	after_generate(cmd, ctx)           # hook: e.g., mark location end
	
	return ctx.result

# Hook methods (default no-op, subclasses override)
func before_generate(cmd: IrCommand, ctx: GenerationContext):
	pass
	
func after_generate(cmd: IrCommand, ctx: GenerationContext):
	pass

func expand_template(cmd: IrCommand, ctx: GenerationContext):
	var tmpl: Template = _template_registry.get_template(cmd.get_opcode())
	var resolved: String = _operand_resolver.resolve(tmpl.body, cmd)
	ctx.result = GeneratedInstruction.new(resolved, tmpl.size)
```

**Subclass for debug mode**:
```gdscript
class_name DebugInstructionGenerator extends InstructionGenerator

func before_generate(cmd: IrCommand, ctx: GenerationContext):
	ctx.add_header("# %s from %s\n" % [cmd.get_opcode(), cmd.loc])
	# mark location begin

func after_generate(cmd: IrCommand, ctx: GenerationContext):
	# mark location end
	pass
```

### Pattern 5: Composite Pattern — Assembly Block Hierarchy

**Intent**: Compose objects into tree structures to represent part-whole hierarchies.

**Current problem**: Assembly blocks are flat text. There's no structured representation — you can't inspect sub-blocks, iterate over instructions, or apply transformations at different granularities.

**Design**:

```
┌──────────────────────┐
│   AssyComponent      │  (abstract interface)
├──────────────────────┤
│ + get_text() -> str  │
│ + get_size() -> int  │
│ + get_locations()    │
└──────────────────────┘
        ▲
        │
┌──────────────────────┐      ┌──────────────────────────┐
│   AssyInstruction    │      │   AssyBlock (Composite)  │
├──────────────────────┤      ├──────────────────────────┤
│ - text: String       │      │ - children: AssyComp[]   │
│ - size: int          │      │ - label: String          │
│ - loc: LocationRange │      │ - loc_map: LocationMap   │
│ + get_text()         │      │ + get_text() → concat    │
│ + get_size()         │      │ + get_size() → sum       │
└──────────────────────┘      │ + add(child)             │
                              │ + remove(child)          │
                              │ + get_child(idx)         │
                              └──────────────────────────┘
```

**Usage**:
```gdscript
var function_block = AssyBlock.new("my_function")
function_block.add(AssyInstruction.new("mov EAX, 5;\n", 8))
var if_block = AssyBlock.new("if_cond")
if_block.add(AssyInstruction.new("cmp EAX, 0;\n", 8))
if_block.add(AssyInstruction.new("jz else_lbl;\n", 8))
function_block.add(if_block)

# Uniform traversal
var all_text = function_block.get_text()  # recursively concatenates
var total_size = function_block.get_size() # recursively sums
```

### Pattern 6: Decorator Pattern — Augmenting Assembly Emission

**Intent**: Attach additional responsibilities to an object dynamically.

**Current problem**: Debug tracing, location tracking, and IR tracing are interleaved with emission logic via boolean constants [`ADD_DEBUG_TRACE`](../scenes/codegen_md.gd:7), [`ADD_IR_TRACE`](../scenes/codegen_md.gd:8).

**Design**:

```
┌──────────────────────────┐
│   AssyEmitter            │  (abstract component)
├──────────────────────────┤
│ + emit(text, size, loc)  │
└──────────────────────────┘
        ▲
        │
┌──────────────────────────┐
│   BaseAssyEmitter        │  (concrete component)
├──────────────────────────┤
│ - output: AssyBlock      │
│ + emit(text, size, loc)  │
└──────────────────────────┘
        ▲
        │ decorated by
        │
┌─────────────────────────────┐
│   DebugTraceDecorator       │  (decorator)
├─────────────────────────────┤
│ - wrapped: AssyEmitter      │
│ + emit(text, size, loc)     │
│   → wrapped.emit(           │
│       "#trace\n" + text,    │
│       size, loc)            │
└─────────────────────────────┘

┌──────────────────────────────────┐
│   LocationTrackingDecorator      │  (decorator)
├──────────────────────────────────┤
│ - wrapped: AssyEmitter           │
│ - loc_map: LocationMap           │
│ + emit(text, size, loc)          │
│   → track_location(loc)          │
│   → wrapped.emit(text, size, loc)│
└──────────────────────────────────┘
```

**Usage**:
```gdscript
var base = BaseAssyEmitter.new(output_block)

# Dynamically compose decorations
var emitter: AssyEmitter = base
if config.enable_debug_trace:
	emitter = DebugTraceDecorator.new(emitter)
if config.enable_loc_tracking:
	emitter = LocationTrackingDecorator.new(emitter)

# All codegen goes through the decorated interface
emitter.emit("mov EAX, 5;\n", 8, some_location)
```

### Pattern 7: Prototype Pattern — Template Cloning

**Intent**: Specify the kinds of objects to create using a prototypical instance, and create new objects by copying this prototype.

**Current problem**: [`op_map`](../scenes/codegen_md.gd:12) is a flat dictionary. When a template is used, its parameters are substituted in-place via string replacement. There's no "template instance" that can be parameterized.

**Design**:

```gdscript
class_name Template
extends Reference

var body: String      # "mov $dest, $src;\n"
var size: int         # 8
var params: Dictionary = {}  # {"dest": "EAX", "src": "5"}

func with_params(new_params: Dictionary) -> Template:
	var clone = self.duplicate()
	clone.params = new_params.duplicate()
	return clone

func resolve() -> String:
	var text = body
	for key in params:
		text = text.replace("$%s" % key, params[key])
	return text

# -----

class_name TemplateRegistry
extends Reference

var _prototypes: Dictionary = {}  # opcode → Template

func register(opcode: String, prototype: Template):
	_prototypes[opcode] = prototype

func instantiate(opcode: String, params: Dictionary) -> Template:
	var proto = _prototypes[opcode]
	assert(proto != null, "Unknown opcode: %s" % opcode)
	return proto.with_params(params)
```

**Template data file** ([`templates/mov.yaml`](../templates/mov.yaml)):
```yaml
MOV:
  body: "mov $dest, $src;\n"
  size: 8
  params:
    - dest
    - src
ADD:
  body: "add $a, $b;\n"
  size: 8
  params:
    - a
    - b
IF:
  body: |
    $cond_block
    cmp $result, 0;
    jz $else_label;
    $then_block
    jmp $end_label;
    $else_label:
  size: null  # computed dynamically
  params:
    - cond_block
    - result
    - else_label
    - then_block
    - end_label
```

### Pattern 8: Chain of Responsibility — Operand Resolution Pipeline

**Intent**: Avoid coupling the sender of a request to its receiver by giving more than one object a chance to handle the request.

**Current problem**: [`load_value()`](../scenes/codegen_md.gd:551) is a single function with a `match` on storage type. Adding a new storage type requires modifying that function.

**Design**:

```gdscript
class_name OperandResolver
extends Reference

var _handlers: Array[OperandHandler] = []

func add_handler(handler: OperandHandler):
	_handlers.append(handler)

func resolve(operand: Operand) -> String:
	for handler in _handlers:
		if handler.can_handle(operand):
			return handler.resolve(operand)
	push_error("No handler for operand: %s" % operand)
	return ""

# -----

class_name OperandHandler
extends Reference

func can_handle(operand: Operand) -> bool:
	push_error("abstract")
	return false

func resolve(operand: Operand) -> String:
	push_error("abstract")
	return ""

# -----

class_name GlobalHandler extends OperandHandler
func can_handle(op: Operand) -> bool:
	return op.storage_type == "global"
func resolve(op: Operand) -> String:
	return "*%s" % op.symbol_name

class_name StackHandler extends OperandHandler
func can_handle(op: Operand) -> bool:
	return op.storage_type == "stack"
func resolve(op: Operand) -> String:
	return "EBP[%d]" % op.offset

class_name ImmediateHandler extends OperandHandler
func can_handle(op: Operand) -> bool:
	return op.storage_type == "immediate"
func resolve(op: Operand) -> String:
	return op.value

class_name RegisterHandler extends OperandHandler
func can_handle(op: Operand) -> bool:
	return op.storage_type == "register"
func resolve(op: Operand) -> String:
	return op.register_name
```

**Usage**:
```gdscript
var resolver = OperandResolver.new()
resolver.add_handler(ImmediateHandler.new())
resolver.add_handler(RegisterHandler.new())
resolver.add_handler(GlobalHandler.new())
resolver.add_handler(StackHandler.new())

# To add a new storage type (e.g., "thread_local"):
resolver.add_handler(ThreadLocalHandler.new())
```

### Pattern 9: Mediator Pattern — Codegen Orchestration

**Intent**: Define an object that encapsulates how a set of objects interact.

**Current problem**: [`generate()`](../scenes/codegen_md.gd:143) directly orchestrates everything: it calls `allocate_vars()`, pushes/pops scope blocks, creates `AssyBlock`s, tracks `referenced_cbs`, calls `fixup_enter_leave()`, calls `generate_globals()`, and emits signals. There's no separation between orchestration and execution.

**Design**:

```
┌─────────────────────────────────────────────┐
│              CodegenMediator                 │  (mediator)
├─────────────────────────────────────────────┤
│ - template_reg: TemplateRegistry            │
│ - reg_alloc: RegisterAllocator              │
│ - stor_alloc: StorageAllocator              │
│ - emitter: AssyEmitter                      │
│ - visitor: IrCommandVisitor                 │
│ - resolver: OperandResolver                 │
├─────────────────────────────────────────────┤
│ + generate(ir_yaml: String) -> AssemblyResult│
│ + generate_block(block_id) -> AssyBlock     │
│ + resolve_scope(scope_id)                   │
│ + on_block_referenced(block_id)             │
└─────────────────────────────────────────────┘
        │
        │ collaborates with
        ▼
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│Template  │ │Register  │ │Storage   │ │Assy     │ │Operand   │
│Registry  │ │Allocator │ │Allocator │ │Emitter  │ │Resolver  │
└──────────┘ └──────────┘ └──────────┘ └──────────┘ └──────────┘
```

**Key**:
- Components don't know about each other — they only know the `Mediator`
- The `Mediator` is the single place where the codegen pipeline is defined
- Adding a preprocessing or postprocessing step only changes the `Mediator`, not the individual components

### Pattern 10: State Pattern — Codegen Phase Management

**Intent**: Allow an object to alter its behavior when its internal state changes.

**Current problem**: The codegen has implicit phases (deserialization→allocation→generation→fixup) but they're managed by checking global state and ad-hoc stacks ([`cb_stack`](../scenes/codegen_md.gd:35), [`assy_block_stack`](../scenes/codegen_md.gd:29), [`entered_scopes`](../scenes/codegen_md.gd:36)).

**Design**:

```gdscript
class_name CodegenState
extends Reference
func enter(ctx: CodegenContext): pass
func exit(ctx: CodegenContext): pass
func process(ctx: CodegenContext, input) -> bool:  return false  # false = done

class_name ParsingState extends CodegenState
func process(ctx: CodegenContext, input) -> bool:
	ctx.ir_data = parse_yaml(input)
	ctx.change_state(AllocationState.new())
	return true  # continue processing

class_name AllocationState extends CodegenState
func enter(ctx: CodegenContext):
	ctx.stor_alloc.allocate_all(ctx.ir_data)

func process(ctx: CodegenContext, input) -> bool:
	var referenced = input as String  # code block name
	ctx.emitter.emit_block(referenced)
	return true

class_name FixupState extends CodegenState
func process(ctx: CodegenContext, _input) -> bool:
	ctx.assy_block.fixup_enter_leave(ctx.ir_data.scopes)
	ctx.change_state(CompletedState.new())
	return true

class_name CompletedState extends CodegenState
func process(ctx: CodegenContext, _input) -> bool:
	return false  # terminal

# -----

class_name CodegenContext
extends Reference
var state: CodegenState
var ir_data: Dictionary
var emitter: AssyEmitter
var assy_block: AssyBlock
var stor_alloc: StorageAllocator

func change_state(new_state: CodegenState):
	if state: state.exit(self)
	state = new_state
	state.enter(self)
```

---

## 4. Architecture Overview

### 4.1 Class Diagram

```
┌────────────────────────────────────────────────────────────────────┐
│                      CodegenMediator                                │
├────────────────────────────────────────────────────────────────────┤
│ - template_reg:    TemplateRegistry                                │
│ - emitter:         AssyEmitter           (with Decorators)         │
│ - visitor:         AssemblyEmitterVisitor                          │
│ - reg_alloc:       RegisterAllocator     (Strategy)                │
│ - stor_alloc:      StorageAllocator      (Strategy)                │
│ - oper_resolver:   OperandResolver       (Chain of Responsibility) │
│ - state_machine:   CodegenContext        (State)                   │
├────────────────────────────────────────────────────────────────────┤
│ + generate(ir_yaml: String) → String                              │
│ + generate_block(block_id: String) → AssyComponent                │
│ + register_template(opcode: String, template: Template)           │
└────────────────────────────────────────────────────────────────────┘
        │
        │ uses
        ├────────────────────────────────────────────────────────────┐
        │                                                            │
        ▼                                                            ▼
┌──────────────────────────┐          ┌──────────────────────────────┐
│   IrCommandVisitor       │          │   TemplateRegistry            │
│   (interface)            │◄─uses────│   (contains Prototypes)       │
│                          │          │                              │
│   AssemblyEmitterVisitor │          │   + get_template(opcode)      │
│   (implementation)       │          │   + instantiate(op, params)   │
└──────────────────────────┘          └──────────────────────────────┘
        │                                                            │
        │ emits to                                                   │ provides templates
        ▼                                                            │
┌──────────────────────────┐          ┌──────────────────────────────┐
│   AssyEmitter            │          │   Template (Prototype)        │
│   (Decoratable)          │          │                              │
│                          │          │   + with_params(dict)         │
│   BaseAssyEmitter        │          │   + resolve() → String        │
│   DebugTraceDecorator    │          └──────────────────────────────┘
│   LocTrackingDecorator   │
└──────────────────────────┘
        │
        │ produces
        ▼
┌──────────────────────────┐          ┌──────────────────────────────┐
│   AssyComponent          │          │   RegisterAllocator           │
│   (Composite)            │          │   (Strategy)                  │
│                          │          │                              │
│   AssyInstruction        │          │   + allocate(operand)         │
│   AssyBlock (Composite)  │          │   + free(reg)                 │
└──────────────────────────┘          └──────────────────────────────┘

┌──────────────────────────┐          ┌──────────────────────────────┐
│   OperandResolver         │          │   StorageAllocator            │
│   (Chain of Responsibility)│         │   (Strategy)                  │
│                          │          │                              │
│   + add_handler(handler) │          │   + allocate(var, scope)      │
│   + resolve(operand)     │          │   + allocate_temp(scope)      │
│   ───────────────────    │          └──────────────────────────────┘
│   GlobalHandler          │
│   StackHandler           │          ┌──────────────────────────────┐
│   ImmediateHandler       │          │   CodegenContext              │
│   RegisterHandler        │          │   (State)                     │
└──────────────────────────┘          │                              │
                                      │   + change_state(state)       │
                                      │   + process(input) → bool     │
                                      └──────────────────────────────┘
```

### 4.2 Sequence Diagram — Single IR Command Generation

```
Visitor                 Template            OperandResolver     RegisterAllocator     AssyEmitter
  │                        │                      │                   │                   │
  │  cmd.accept(visitor)   │                      │                   │                   │
  │───────────────────────►│                      │                   │                   │
  │                        │                      │                   │                   │
  │  visit_mov(cmd)        │                      │                   │                   │
  │◄───────────────────────│                      │                   │                   │
  │                        │                      │                   │                   │
  │  reg.get_template(MOV) │                      │                   │                   │
  │──────────────────────────────────────────────►│                   │                   │
  │                        │                      │                   │                   │
  │  Template              │                      │                   │                   │
  │◄──────────────────────────────────────────────│                   │                   │
  │                        │                      │                   │                   │
  │  inst = t.with_params  │                      │                   │                   │
  │  ({dest: cmd.dest,     │                      │                   │                   │
  │   src: cmd.src})       │                      │                   │                   │
  │                        │                      │                   │                   │
  │  resolver.resolve(dest)│                      │                   │                   │
  │──────────────────────────────────────────────►│                   │                   │
  │                        │                      │  resolve via      │                   │
  │                        │                      │  handler chain     │                   │
  │                        │                      │◄──────────────────►│                   │
  │  resolved_dest         │                      │                   │                   │
  │◄──────────────────────────────────────────────│                   │                   │
  │                        │                      │                   │                   │
  │  if temp needed:       │                      │                   │                   │
  │  reg_alloc.allocate()  │                      │                   │                   │
  │──────────────────────────────────────────────────────────────────►│                   │
  │  register_name         │                      │                   │                   │
  │◄──────────────────────────────────────────────────────────────────│                   │
  │                        │                      │                   │                   │
  │  emitter.emit(text,    │                      │                   │                   │
  │   size, loc)           │                      │                   │                   │
  │─────────────────────────────────────────────────────────────────────────────────────►│
  │                        │                      │                   │                   │
```

### 4.3 Package/File Structure

```
scenes/
├── codegen/                              # NEW: all codegen components
│   ├── codegen_mediator.gd               # Mediator — the entry point
│   ├── codegen_state.gd                  # State — phase management
│   │
│   ├── cmd/                              # Command pattern — IR commands
│   │   ├── ir_command.gd                 # Abstract IrCommand base
│   │   ├── ir_cmd_mov.gd                 # IrCmdMov
│   │   ├── ir_cmd_op.gd                  # IrCmdOp
│   │   ├── ir_cmd_if.gd                  # IrCmdIf
│   │   ├── ir_cmd_else_if.gd             # IrCmdElseIf
│   │   ├── ir_cmd_else.gd                # IrCmdElse
│   │   ├── ir_cmd_while.gd               # IrCmdWhile
│   │   ├── ir_cmd_call.gd                # IrCmdCall
│   │   ├── ir_cmd_call_indirect.gd       # IrCmdCallIndirect
│   │   ├── ir_cmd_return.gd              # IrCmdReturn
│   │   ├── ir_cmd_enter.gd               # IrCmdEnter
│   │   ├── ir_cmd_leave.gd               # IrCmdLeave
│   │   ├── ir_cmd_alloc.gd               # IrCmdAlloc
│   │   ├── ir_cmd_mov_arr.gd             # IrCmdMovArr
│   │   └── ir_command_visitor.gd         # Visitor interface
│   │
│   ├── visitor/                          # Visitor — code generation
│   │   ├── assembly_emitter_visitor.gd   # Main visitor implementation
│   │   └── ir_command_serializer.gd      # Alternative visitor: serialize back to YAML
│   │
│   ├── template/                         # Prototype + Strategy — templates
│   │   ├── template.gd                   # Template (Prototype)
│   │   ├── template_registry.gd          # Registry
│   │   ├── yaml_template_loader.gd       # Loads from YAML data files
│   │   └── inline_template_provider.gd   # For backward compat
│   │
│   ├── alloc/                            # Strategy — allocation
│   │   ├── register_allocator.gd         # Abstract interface
│   │   ├── linear_scan_allocator.gd      # 4-register linear scan
│   │   ├── storage_allocator.gd          # Abstract interface
│   │   ├── simple_stack_allocator.gd     # EBP-relative stack alloc
│   │   └── global_symbol_allocator.gd    # Global label alloc
│   │
│   ├── emit/                             # Decorator + Composite — assembly emission
│   │   ├── assy_emitter.gd               # Abstract decoratable interface
│   │   ├── base_assy_emitter.gd          # Concrete component
│   │   ├── debug_trace_decorator.gd      # Decorator: debug comments
│   │   ├── location_decorator.gd         # Decorator: location tracking
│   │   ├── assy_component.gd             # Composite interface
│   │   ├── assy_instruction.gd           # Leaf in composite
│   │   └── assy_block_composite.gd       # Composite node
│   │
│   ├── resolve/                          # Chain of Responsibility — operand resolution
│   │   ├── operand_resolver.gd           # Chain manager
│   │   ├── operand_handler.gd            # Abstract handler
│   │   ├── global_handler.gd             # *label
│   │   ├── stack_handler.gd              # EBP[offset]
│   │   ├── immediate_handler.gd          # literal value
│   │   └── register_handler.gd           # register name
│   │
│   └── data/                             # Template data files (YAML)
│       ├── templates_mov.yaml
│       ├── templates_arith.yaml
│       ├── templates_control.yaml
│       └── templates_call.yaml
```

---

## 5. Data-Driven Template Specification

### 5.1 Template YAML Format

Data files are YAML-based. Each template specifies:
- The assembly body with `$param` placeholders
- The expected parameters (for validation)
- The instruction size (or `null` for computed sizes)
- Optional: register constraints, operand types

**File: [`templates_mov.yaml`](../scenes/codegen/data/templates_mov.yaml)**
```yaml
MOV:
  body: "mov $dest, $src;\n"
  size: 8
  params:
    - name: dest
      type: writable_operand  # must be a register or memory
    - name: src
      type: readable_operand   # can be register, memory, or immediate
  doc: "Move src into dest"

MOV_ARR:
  body: |
    mov $tmp, $dest;
    $inits
  size: null  # computed
  params:
    - name: tmp
      type: register
    - name: dest
      type: writable_operand
    - name: inits
      type: generated_block  # expanded by visitor
  doc: "Initialize array elements"
```

**File: [`templates_control.yaml`](../scenes/codegen/data/templates_control.yaml)**
```yaml
IF:
  body: |
    $cond_code
    cmp $result, 0;
    jz $else_lbl;
    $then_code
    jmp $end_lbl;
    $else_lbl:
  size: null  # computed from children
  params:
    - cond_code: generated_block
    - result: readable_operand
    - else_lbl: label
    - then_code: generated_block
    - end_lbl: label

WHILE:
  body: |
    $loop_lbl:
    $cond_code
    cmp $result, 0;
    jz $end_lbl;
    $body_code
    jmp $loop_lbl;
    $end_lbl:
  size: null
  params:
    - loop_lbl: label
    - cond_code: generated_block
    - result: readable_operand
    - end_lbl: label
    - body_code: generated_block
```

**File: [`templates_call.yaml`](../scenes/codegen/data/templates_call.yaml)**
```yaml
CALL:
  body: |
    $push_args
    call @$fun;
    add ESP, $stack_size;
    mov ^$res, EAX;
  size: null
  params:
    - push_args: generated_block
    - fun: function_label
    - stack_size: immediate
    - res: writable_operand

CALL_INDIRECT:
  body: |
    $push_args
    call $fun_ptr;
    add ESP, $stack_size;
    mov ^$res, EAX;
  size: null
  params:
    - push_args: generated_block
    - fun_ptr: readable_operand
    - stack_size: immediate
    - res: writable_operand
```

### 5.2 Template Validation

[`TemplateRegistry`](../scenes/codegen/template/template_registry.gd) validates at registration time:

```gdscript
func register(opcode: String, template: Template):
	assert(template.params.size() > 0, "Template must have at least one param")
	assert(template.body.find("$") != -1, "Template body must contain at least one $param reference")
	
	# Validate that all $params in body are declared
	var body_params = _extract_params(template.body)
	for bp in body_params:
		assert(bp in template.params_dict, 
			"Template %s: body uses $%s but it's not declared in params" % [opcode, bp])
	
	_prototypes[opcode] = template
```

---

## 6. Implementation Plan

### Phase 1: Foundation (Week 1)

| Step | File(s) | Pattern | Description |
|------|---------|---------|-------------|
| 1.1 | [`cmd/ir_command.gd`](../scenes/codegen/cmd/ir_command.gd) | **Command** | Create abstract `IrCommand` base class |
| 1.2 | [`cmd/ir_cmd_*.gd`](../scenes/codegen/cmd/) | **Command** | Create 12 concrete command classes, extracting operands from flat arrays |
| 1.3 | [`cmd/ir_command_visitor.gd`](../scenes/codegen/cmd/ir_command_visitor.gd) | **Visitor** | Create visitor interface with 12 `visit_*` methods |
| 1.4 | [`template/template.gd`](../scenes/codegen/template/template.gd) | **Prototype** | Create `Template` class with `with_params()` and `resolve()` |
| 1.5 | [`template/template_registry.gd`](../scenes/codegen/template/template_registry.gd) | **Prototype** | Create registry with YAML loading and validation |
| 1.6 | [`data/templates_*.yaml`](../scenes/codegen/data/) | Data | Write all template YAML files |

### Phase 2: Allocation (Week 2)

| Step | File(s) | Pattern | Description |
|------|---------|---------|-------------|
| 2.1 | [`alloc/register_allocator.gd`](../scenes/codegen/alloc/register_allocator.gd) | **Strategy** | Create abstract register allocator interface |
| 2.2 | [`alloc/linear_scan_allocator.gd`](../scenes/codegen/alloc/linear_scan_allocator.gd) | **Strategy** | Implement 4-register linear scan (replacing ad-hoc dict) |
| 2.3 | [`alloc/storage_allocator.gd`](../scenes/codegen/alloc/storage_allocator.gd) | **Strategy** | Create abstract storage allocator interface |
| 2.4 | [`alloc/simple_stack_allocator.gd`](../scenes/codegen/alloc/simple_stack_allocator.gd) | **Strategy** | Implement EBP-relative stack allocation |
| 2.5 | [`alloc/global_symbol_allocator.gd`](../scenes/codegen/alloc/global_symbol_allocator.gd) | **Strategy** | Implement global label allocation |

### Phase 3: Emission (Week 3)

| Step | File(s) | Pattern | Description |
|------|---------|---------|-------------|
| 3.1 | [`emit/assy_emitter.gd`](../scenes/codegen/emit/assy_emitter.gd) | **Decorator** | Create abstract emitter interface |
| 3.2 | [`emit/base_assy_emitter.gd`](../scenes/codegen/emit/base_assy_emitter.gd) | **Decorator** | Implement base (writes to output) |
| 3.3 | [`emit/debug_trace_decorator.gd`](../scenes/codegen/emit/debug_trace_decorator.gd) | **Decorator** | Implement debug trace wrapping |
| 3.4 | [`emit/location_decorator.gd`](../scenes/codegen/emit/location_decorator.gd) | **Decorator** | Implement location tracking wrapping |
| 3.5 | [`emit/assy_component.gd`](../scenes/codegen/emit/assy_component.gd) | **Composite** | Create abstract assembly component |
| 3.6 | [`emit/assy_instruction.gd`](../scenes/codegen/emit/assy_instruction.gd) | **Composite** | Create leaf (single instruction) |
| 3.7 | [`emit/assy_block_composite.gd`](../scenes/codegen/emit/assy_block_composite.gd) | **Composite** | Create composite (nested block) |

### Phase 4: Resolution (Week 4)

| Step | File(s) | Pattern | Description |
|------|---------|---------|-------------|
| 4.1 | [`resolve/operand_resolver.gd`](../scenes/codegen/resolve/operand_resolver.gd) | **Chain of Resp.** | Create resolver that chains handlers |
| 4.2 | [`resolve/operand_handler.gd`](../scenes/codegen/resolve/operand_handler.gd) | **Chain of Resp.** | Create abstract handler base |
| 4.3 | [`resolve/*_handler.gd`](../scenes/codegen/resolve/) | **Chain of Resp.** | Create 4 concrete handlers |
| 4.4 | [`visitor/assembly_emitter_visitor.gd`](../scenes/codegen/visitor/assembly_emitter_visitor.gd) | **Visitor** | Implement the full visitor that uses all other components |

### Phase 5: Orchestration (Week 5)

| Step | File(s) | Pattern | Description |
|------|---------|---------|-------------|
| 5.1 | [`codegen_state.gd`](../scenes/codegen/codegen_state.gd) | **State** | Create state machine for pipeline phases |
| 5.2 | [`codegen_mediator.gd`](../scenes/codegen/codegen_mediator.gd) | **Mediator** | Create mediator that wires everything together |
| 5.3 | Integration test | — | Replace call to `codegen_md.gd.parse_file()` with `CodegenMediator.generate()` |
| 5.4 | Remove old file | — | Deprecate `codegen_md.gd` |

---

## 7. Comparison: GoF vs. Current Codebase

| Aspect | Current (`codegen_md.gd`) | GoF Design |
|--------|---------------------------|------------|
| Command dispatch | `match cmd.words[0]` (procedural switch) | **Visitor** pattern on typed command objects |
| Templates | Hardcoded string constants in `op_map` | **Prototype** + YAML data files, validated at startup |
| Operand resolution | `load_value()` with one big `match` | **Chain of Responsibility** with pluggable handlers |
| Register allocation | Ad-hoc dictionary `regs_in_use` | **Strategy** pattern with pluggable allocators |
| Storage allocation | Inline in `allocate_value()` | **Strategy** pattern, separated by scope type |
| Assembly representation | Flat text + `write_pos` integer | **Composite** pattern with tree structure |
| Debug/location | Boolean flags + inline conditionals | **Decorator** pattern wrapping the emitter |
| Pipeline orchestration | One big `generate()` function | **Mediator** + **State** pattern |
| Adding new opcode | Modify 3 things: match, fn, op_map | Add 1 command class + 1 visitor method |
| Adding new storage type | Modify `load_value/address_value/store_val` | Add 1 handler to the chain |
| Adding new target | Fork the whole file | New visitor implementation (same Template data) |
| Testing | Integration-only (must supply full IR) | Unit-testable: each pattern in isolation |
| Coupling | Tight (everything reads `all_syms`) | Loose (components depend on interfaces) |
| Cohesion | Low (833 lines, 10+ responsibilities) | High (~20 focused classes, each with 1 reason to change) |

---

## 8. Migration Strategy

The replacement will be **incremental**, not a big-bang rewrite:

### Step 1: Parallel Implementation (Phases 1-5)
- New codegen lives in [`scenes/codegen/`](../scenes/codegen/)
- Old [`codegen_md.gd`](../scenes/codegen_md.gd) remains untouched
- New codegen is tested against the same test suite as the old one

### Step 2: Adapter Layer
Create a thin adapter that wraps [`CodegenMediator`](../scenes/codegen/codegen_mediator.gd) to match the old API:

```gdscript
# In codegen_md.gd (modified)
func parse_file(input: Dictionary) -> String:
	var mediator = CodegenMediator.new()
	mediator.template_registry.load_from_directory("res://scenes/codegen/data/")
	return mediator.generate(input.filename)
```

### Step 3: A/B Comparison
Run both codegens side-by-side:
```gdscript
var old_result = _old_codegen.parse_file(input)
var new_result = _new_codegen_mediator.generate(input.filename)
assert(old_result == new_result, "Codegen mismatch!")
```

### Step 4: Flip the Switch
Once all tests pass, delete the old [`codegen_md.gd`](../scenes/codegen_md.gd) and rename the new one.

---

## 9. Class Dictionary (Summary)

| Class | File | GoF Pattern | Responsibility |
|-------|------|-------------|----------------|
| `IrCommand` | [`cmd/ir_command.gd`](../scenes/codegen/cmd/ir_command.gd) | **Command** | Abstract base for all IR commands |
| `IrCmdMov` | [`cmd/ir_cmd_mov.gd`](../scenes/codegen/cmd/ir_cmd_mov.gd) | **Command** | MOV command with typed dest/src |
| `IrCmdOp` | [`cmd/ir_cmd_op.gd`](../scenes/codegen/cmd/ir_cmd_op.gd) | **Command** | Arithmetic operations |
| `IrCmdIf` | [`cmd/ir_cmd_if.gd`](../scenes/codegen/cmd/ir_cmd_if.gd) | **Command** | Conditional branch |
| `IrCmdWhile` | [`cmd/ir_cmd_while.gd`](../scenes/codegen/cmd/ir_cmd_while.gd) | **Command** | Loop construct |
| `IrCmdCall` | [`cmd/ir_cmd_call.gd`](../scenes/codegen/cmd/ir_cmd_call.gd) | **Command** | Function call |
| `IrCmdReturn` | [`cmd/ir_cmd_return.gd`](../scenes/codegen/cmd/ir_cmd_return.gd) | **Command** | Function return |
| `IrCmdEnter` | [`cmd/ir_cmd_enter.gd`](../scenes/codegen/cmd/ir_cmd_enter.gd) | **Command** | Scope entry |
| `IrCmdLeave` | [`cmd/ir_cmd_leave.gd`](../scenes/codegen/cmd/ir_cmd_leave.gd) | **Command** | Scope exit |
| `IrCmdAlloc` | [`cmd/ir_cmd_alloc.gd`](../scenes/codegen/cmd/ir_cmd_alloc.gd) | **Command** | Array allocation |
| `IrCmdMovArr` | [`cmd/ir_cmd_mov_arr.gd`](../scenes/codegen/cmd/ir_cmd_mov_arr.gd) | **Command** | Array element init |
| `IrCommandVisitor` | [`cmd/ir_command_visitor.gd`](../scenes/codegen/cmd/ir_command_visitor.gd) | **Visitor** | Interface for ops on command hierarchy |
| `AssemblyEmitterVisitor` | [`visitor/assembly_emitter_visitor.gd`](../scenes/codegen/visitor/assembly_emitter_visitor.gd) | **Visitor** | Main codegen: each visit generates assembly |
| `Template` | [`template/template.gd`](../scenes/codegen/template/template.gd) | **Prototype** | Template with `with_params` cloning |
| `TemplateRegistry` | [`template/template_registry.gd`](../scenes/codegen/template/template_registry.gd) | **Prototype** | Loads, validates, and stores templates |
| `YamlTemplateLoader` | [`template/yaml_template_loader.gd`](../scenes/codegen/template/yaml_template_loader.gd) | **Strategy** | YAML file → Template objects |
| `RegisterAllocator` | [`alloc/register_allocator.gd`](../scenes/codegen/alloc/register_allocator.gd) | **Strategy** | Abstract register allocation |
| `LinearScanAllocator` | [`alloc/linear_scan_allocator.gd`](../scenes/codegen/alloc/linear_scan_allocator.gd) | **Strategy** | 4-register linear scan |
| `StorageAllocator` | [`alloc/storage_allocator.gd`](../scenes/codegen/alloc/storage_allocator.gd) | **Strategy** | Abstract storage allocation |
| `SimpleStackAllocator` | [`alloc/simple_stack_allocator.gd`](../scenes/codegen/alloc/simple_stack_allocator.gd) | **Strategy** | EBP-relative stack allocation |
| `GlobalSymbolAllocator` | [`alloc/global_symbol_allocator.gd`](../scenes/codegen/alloc/global_symbol_allocator.gd) | **Strategy** | Global label allocation |
| `AssyEmitter` | [`emit/assy_emitter.gd`](../scenes/codegen/emit/assy_emitter.gd) | **Decorator** | Abstract emitter interface |
| `BaseAssyEmitter` | [`emit/base_assy_emitter.gd`](../scenes/codegen/emit/base_assy_emitter.gd) | **Decorator** | Writes text to output |
| `DebugTraceDecorator` | [`emit/debug_trace_decorator.gd`](../scenes/codegen/emit/debug_trace_decorator.gd) | **Decorator** | Adds debug comments |
| `LocationDecorator` | [`emit/location_decorator.gd`](../scenes/codegen/emit/location_decorator.gd) | **Decorator** | Tracks source locations |
| `AssyComponent` | [`emit/assy_component.gd`](../scenes/codegen/emit/assy_component.gd) | **Composite** | Abstract assembly tree node |
| `AssyInstruction` | [`emit/assy_instruction.gd`](../scenes/codegen/emit/assy_instruction.gd) | **Composite** | Leaf (single instruction) |
| `AssyBlockComposite` | [`emit/assy_block_composite.gd`](../scenes/codegen/emit/assy_block_composite.gd) | **Composite** | Composite (nested block) |
| `OperandResolver` | [`resolve/operand_resolver.gd`](../scenes/codegen/resolve/operand_resolver.gd) | **Chain of Resp.** | Routes operands to handlers |
| `OperandHandler` | [`resolve/operand_handler.gd`](../scenes/codegen/resolve/operand_handler.gd) | **Chain of Resp.** | Abstract handler |
| `CodegenState` | [`codegen_state.gd`](../scenes/codegen/codegen_state.gd) | **State** | Abstract pipeline phase |
| `CodegenContext` | [`codegen_state.gd`](../scenes/codegen/codegen_state.gd) | **State** | State machine context |
| `CodegenMediator` | [`codegen_mediator.gd`](../scenes/codegen/codegen_mediator.gd) | **Mediator** | Orchestrates all components |

**Total: ~30 new files**, each with a single focused responsibility. Compare to 1 file of 833 lines.
