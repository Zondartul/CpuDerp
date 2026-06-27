# Lisp/Macro-Driven Critique of All 9 Codegen Plans

**Persona**: Lisp / Macro-Driven Advocate  
**Date**: 2026-06-27  
**Reference Plan**: [`./plans/lisp_macro_codegen_plan.md`](lisp_macro_codegen_plan.md)

---

## Executive Summary

From the Lisp perspective, a codegen is fundamentally a **macro expansion pipeline**: IR commands are macro invocations, templates are macro definitions, and passes are macro transformers. The ideal codegen treats **everything as data** — S-expressions flowing through composable transforms toward a final representation.

I evaluated each plan on: homoiconicity potential, code-as-data philosophy, metaprogramming capability, extensibility through macros/transformations, DSL creation support, and whether templates are treated as data or code.

| Plan | Homoiconicity | Code-as-Data | Metaprogramming | Macro Extensibility | DSL Support | Templates as Data | Overall Lisp Score |
|------|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| Functional Purity | ★★☆☆☆ | ★★★★☆ | ★☆☆☆☆ | ★★☆☆☆ | ★★☆☆☆ | ★★★★☆ | **2.5/5** |
| Data-Oriented | ★☆☆☆☆ | ★★★☆☆ | ★☆☆☆☆ | ★☆☆☆☆ | ★★☆☆☆ | ★★★★★ | **2.2/5** |
| Unix Philosophy | ★★☆☆☆ | ★★★★☆ | ★☆☆☆☆ | ★★★☆☆ | ★★☆☆☆ | ★★★★★ | **2.8/5** |
| TDD | ★★☆☆☆ | ★★★☆☆ | ★☆☆☆☆ | ★★☆☆☆ | ★★☆☆☆ | ★★★★☆ | **2.3/5** |
| XP | ★★★☆☆ | ★★★☆☆ | ★☆☆☆☆ | ★★★☆☆ | ★★☆☆☆ | ★★★★☆ | **2.7/5** |
| Design Patterns (GoF) | ★★★★★ | ★☆☆☆☆ | ★★☆☆☆ | ★★★★★ | ★★☆☆☆ | ★☆☆☆☆ | **2.5/5** |
| Literate Programming | ★★★★☆ | ★★★★★ | ★☆☆☆☆ | ★★★☆☆ | ★★★☆☆ | ★★★★★ | **3.3/5** |
| Agile/Scrum | ★★☆☆☆ | ★★★☆☆ | ★☆☆☆☆ | ★★☆☆☆ | ★★☆☆☆ | ★★★☆☆ | **2.2/5** |
| Waterfall/BDUF | ★☆☆☆☆ | ★★☆☆☆ | ★☆☆☆☆ | ★☆☆☆☆ | ★★☆☆☆ | ★★☆☆☆ | **1.3/5** |
| **Lisp/Macro (reference)** | ★★★★★ | ★★★★★ | ★★★★★ | ★★★★★ | ★★★★★ | ★★★★★ | **5.0/5** |

---

## 1. Critique of the Functional Purity Plan

**File**: [`./plans/functional_purity_codegen_plan.md`](functional_purity_codegen_plan.md)

### What It Gets Right (from a Lisp perspective)

The Functional Purity plan shares several deep intuitions with Lisp philosophy:

- **Pure functions = macros as transformations**: The plan's core insight — that the codegen is a pure function `Codegen : IR_Program → AssemblyResult` — aligns beautifully with the Lisp view of macros as pure tree transformers. Each `expand_template` call is effectively a macro expansion step.

- **Referential transparency**: The plan correctly identifies the current codegen's mutable global state as the root of untestability and non-composability. Lisp macros, too, are expected to be referentially transparent (aside from deliberate macro-specific effects like `gensym`).

- **Data-driven templates**: The `Template` records in the functional plan are structurally similar to our macro table entries — pure data describing a transformation. The plan's `Template` struct with `pattern`, `body`, and `slots` is a homoiconic template in all but name.

- **State threading**: The functional plan threads state through return values (`RegAllocState`, `AssemblyResult`), which mirrors how a Lisp macro pass receives an environment and returns a transformed S-expression.

### What It Misses (the Lisp Critique)

- **No homoiconicity**: The plan uses **strings** for template bodies (`"mov ^{2}, ${1};\n"`). These are not S-expressions. They cannot be composed, transformed, or inspected with the same tools used for the rest of the pipeline. A Lisp programmer would represent templates as nested lists:
  ```lisp
  ; What the plan does (strings):
  "mov ^{dest}, ${src};\n"
  
  ; What a Lisp approach would do (S-expressions):
  ( ("mov" (:store dest) (:load src)) )
  ```
  The string representation is a **dark corner** — it must be parsed at expansion time, cannot be pattern-matched structurally, and resists composition.

- **No macro pipeline**: The plan treats each template expansion as an isolated pure function, but there is no concept of **macro passes** — sequential transformations where the output of one pass feeds the next. The Lisp plan uses 5 explicit passes (template expansion → storage allocation → register allocation → label resolution → serialization). The functional plan collapses all of these into one `expand_template` function with a `match` on template types.

- **No gensym / hygiene**: The functional plan has no concept of hygienic label generation. Label names are either passed in or hardcoded. A Lisp macro system would use `gensym` to guarantee unique labels, preventing collisions in nested expansions.

- **No macro-composition operators**: There is no `quasiquote`/`unquote` mechanism. The functional plan uses positional slot markers (`$1`, `^2`) which are opaque — you cannot partially evaluate a template, splice one template into another, or build template-generating functions. Compare with the Lisp plan's `qq()` / `pv()` / `defmacro()` primitives, which enable composable template construction.

- **No syntax abstraction**: The functional plan's `_resolve_slot` dispatch (`match spec.binding`) is a closed world. Adding a new binding type requires modifying the match. In the Lisp approach, binding types are data (just another S-expression type) and can be extended by adding new pattern variables.

### Summary

| Criterion | Score | Reasoning |
|-----------|:-----:|-----------|
| Homoiconicity potential | ★★☆☆☆ | Templates are strings, not S-expressions. Homiconicity is stated as a goal but not achieved. |
| Code-as-data | ★★★★☆ | Template records, AssemblyResult, and Environment are all data-first. Strong alignment. |
| Metaprogramming capability | ★☆☆☆☆ | No template-generating functions, no quasiquote, no composition operators. |
| Macro extensibility | ★★☆☆☆ | Adding a new template type requires a new `match` arm in `expand_template`. |
| DSL creation | ★★☆☆☆ | String-based templates are a weak DSL. No S-expression DSL embedding. |
| Templates as data vs. code | ★★★★☆ | Template records are pure data. Strongly data-driven. |

The functional purity plan is the **closest cousin** to the Lisp approach — it shares the value-transformation ethos — but it stops short of the full homoiconic vision by keeping templates as strings and missing the macro-pass architecture.

---

## 2. Critique of the Data-Oriented Plan

**File**: [`./plans/data_oriented_codegen_plan.md`](data_oriented_codegen_plan.md)

### What It Gets Right

- **Templates as pre-compiled bytecode**: The plan compiles templates into a flat `PackedInt32Array` of emit opcodes. This is a form of **staged computation** — templates are compiled once, then interpreted efficiently at emit time. A Lisp macro system does something similar at read time (macro-expand once, evaluate many times).

- **Separation of hot/cold paths**: The three-pass pipeline (Analyze → Expand → Fixup) resonates with the Lisp idea of **macro-expansion phases**: you first analyze the form, then rewrite it, then finalize. The plan's Pass 1 (count/allocate) is analogous to a macro's environment-discovery phase.

- **Data is the primary concern**: The plan's slogan "data before code" is Lisp-compatible. The flat arrays, SoA layout, and bitmask register allocator all treat the IR as a mathematical structure to be transformed.

### What It Misses

- **No homiconicity at all**: The plan is aggressively **anti-homoiconic**. It replaces structured data (arrays of IR_Cmd objects) with opaque flat arrays (PackedInt32Array, PackedByteArray). You cannot inspect or manipulate these representations without specialized accessor functions. There is no "code as data" — there is "code as optimized memory layout."

- **Template bytecode is not S-expressions**: The pre-compiled bytecode (`TEXT`, `LOAD`, `STORE`, `TEMP_REG` opcodes) is an imperative instruction set, not a declarative data structure. You cannot pattern-match on bytecode. You cannot compose bytecode sequences with quasiquote. You cannot write macros that generate new bytecode patterns at runtime.

- **No metaprogramming**: The flat data structures are designed for performance, not extensibility. Adding a new instruction type requires modifying the `EmitOp` enum, the `expand_template` match, and the template compilation step. There is no `defmacro` equivalent.

- **Register allocation is hardcoded**: The 4-bit bitmask is elegant but **not extensible**. A Lisp system would define register allocation as a strategy that can be swapped via a higher-order macro (e.g., `with-register-allocation` wrapping a code block). The bitmask is a fixed implementation.

- **No symbol generation**: The plan uses `ir_name` strings for labels. There is no `gensym` facility, no hygienic label creation. The fixup pass (Pass 3) operates on string placeholders — the same approach the current codegen uses.

### Summary

| Criterion | Score | Reasoning |
|-----------|:-----:|-----------|
| Homoiconicity potential | ★☆☆☆☆ | Flat arrays are the opposite of homoiconic. Data is opaque to inspection. |
| Code-as-data | ★★★☆☆ | Templates are data (emit opcodes), but the data is imperative, not declarative. |
| Metaprogramming capability | ★☆☆☆☆ | No runtime code generation, no template composition, no defmacro. |
| Macro extensibility | ★☆☆☆☆ | Adding operations requires modifying enums and compiler functions. |
| DSL creation | ★★☆☆☆ | Template bytecode is a DSL, but it's a low-level, fixed-instruction-set DSL. |
| Templates as data vs. code | ★★★★★ | Templates are pure data — compiled bytecode. Strongly data-driven. |

The data-oriented plan prioritizes **performance** over **expressiveness**. From a Lisp perspective, this is a premature optimization: it sacrifices the homoiconic foundation for cache-friendly memory layout, when a Lisp approach would first get the data model right, then optimize the hot path.

---

## 3. Critique of the Unix Philosophy Plan

**File**: [`./plans/unix_philosophy_codegen_plan.md`](unix_philosophy_codegen_plan.md)

### What It Gets Right

- **Pipelines of small transforms**: The Unix plan's core insight — a codegen is a pipeline of text filters — is structurally similar to the Lisp macro-pass pipeline. Each stage is a pure function: `transform(input: String) -> String`. The Lisp plan's passes also form a pipeline, though operating on S-expressions rather than text.

- **Text as universal interface**: The plan correctly identifies that **text-based intermediate formats enable inspection, debugging, and tool integration**. In the Lisp world, S-expressions play the same role: they are the universal interchange format between macro passes. You can `print` an S-expression at any stage.

- **Templates as separate data files**: The plan stores templates in `templates/templates.tsv` — a text file separate from code. This aligns with the Lisp principle that macros are data (though Lisp macros are data-in-code, not data-in-files).

- **Composability through pipes**: The Unix plan's `ir2flat | sym_alloc | templ_expand | reg_resolve | line_asm` pipeline is composition — the same fundamental idea as composing Lisp macros.

### What It Misses

- **Text is not S-expressions**: The Unix plan's intermediate format is **tab-separated text**, not structured data. A line like `cmd\tcb_0\t0\tMOV\tvar_1\timm_2\t"test.md:12:5"` must be parsed (split on tabs, interpret types) to be used. An S-expression representation would be parsed once and manipulated directly.

- **String templates are fragile**: The templates in `templates.tsv` use `$name`, `@name`, `^name` sigils embedded in strings. This is the **same approach** as the current `op_map` — just moved to a file. The Unix plan has not solved template composition, parameterized templates, or macro-generating macros.

- **No homoiconicity**: Text piping between stages is **serialization/de-serialization at every boundary**. Each stage must parse its input and serialize its output. This adds overhead and loses structural information. A Lisp pipeline passes S-expressions by reference — no parsing overhead between passes.

- **No metaprogramming**: The Unix plan has no concept of macros that write macros. Each stage is a fixed script. There is no way to define new stage types dynamically.

- **No quasiquote**: Template expansion uses string substitution (`$N` → operand value). There is no quasiquote/unquote mechanism for building structured output. The multi-line IF template is a multi-line string with variable markers — not a nested S-expression with unquote slots.

- **Register resolver as separate stage**: The Unix plan has `reg_resolve` as a separate stage that scans for `$`, `@`, `^` markers in text. In the Lisp approach, these markers would be **structural positions** in an S-expression, not characters in a string — they are distinguished by their position in the tree, not by prefix sigils.

### Summary

| Criterion | Score | Reasoning |
|-----------|:-----:|-----------|
| Homoiconicity potential | ★★☆☆☆ | Text piping is a pale imitation of S-expression interchange. Parsing at every stage. |
| Code-as-data | ★★★★☆ | Templates are in TSV files (data). Pipeline stages are pure text transforms. |
| Metaprogramming capability | ★☆☆☆☆ | No runtime code generation. Fixed pipeline of fixed stages. |
| Macro extensibility | ★★★☆☆ | You can insert new stages in the pipeline. Each stage is independently replaceable. |
| DSL creation | ★★☆☆☆ | Template TSV format is a weak DSL. No embedded DSL for complex instructions. |
| Templates as data vs. code | ★★★★★ | Templates are external data files. Clean separation. |

The Unix philosophy plan shares Lisp's love of **composition** and **text-based interchange**, but it substitutes text for S-expressions, losing the structural benefits of homoiconicity. The result is a plan that is more composable than the current codegen but still has a "parse/emit" overhead at every stage boundary.

---

## 4. Critique of the TDD Plan

**File**: [`./plans/tdd_codegen_plan.md`](tdd_codegen_plan.md)

### What It Gets Right

- **Pure functions**: The TDD plan correctly identifies that testability requires pure functions. Every component (`RegAllocState`, `OperandResolver`, `TemplateExpander`) is designed as a pure state machine or pure transformation. This aligns with the Lisp macro approach.

- **Dependency injection**: The plan uses constructor injection for all dependencies. This is structurally similar to how Lisp macros receive an environment — the macro is parameterized by its context, not dependent on global state.

- **Incremental complexity**: The 12 Red-Green-Refactor increments mirror the Lisp tradition of building the language **bottom-up**: start with the simplest case (MOV), then add complexity (OP, IF, CALL, etc.). Each increment adds a tested capability.

### What It Misses

- **No design philosophy, just process**: The TDD plan specifies **how** to build the codegen (test-first, incremental) but not **what** the codegen's architecture should be. It is a testing methodology applied to the problem, not a data-model insight. The Lisp plan specifies both: the what (homoiconic macro expansion) and the how (bottom-up layers).

- **Templates are still strings**: Despite the data-driven framing, the TDD plan uses string-based templates with `$N`, `^N`, `@N` markers. The `_resolve_slots` function scans strings for markers — the same `find_reference` approach, just abstracted behind a method. No S-expressions, no quasiquote, no structural template composition.

- **Register state machine misses the point**: The `RegAllocState` is a pure state machine, which is good for testability. But it's a **linear-scan allocator** with no concept of macro-level register management. In a Lisp codegen, register allocation would be a **macro pass** that rewrites the S-expression tree, not a state machine threaded through every expansion.

- **No macro passes**: The TDD plan's `TemplateExpander` is a monolithic class that handles all command types via `match`. There is no pass pipeline. The expander directly manipulates the assembly buffer. Compare with the Lisp plan where each pass is a separate macro transformer.

- **Test coverage ≠ design quality**: The TDD plan's goal of 100% test coverage is admirable, but it doesn't address whether the design is **extensible** or **homoiconic**. You can TDD a bad design into existence — and the TDD plan's string-based templates, while well-tested, are still string-based.

### Summary

| Criterion | Score | Reasoning |
|-----------|:-----:|-----------|
| Homoiconicity potential | ★★☆☆☆ | No S-expressions. Templates are strings with positional markers. |
| Code-as-data | ★★★☆☆ | Template table is data (const arrays), but bodies are strings, not structured data. |
| Metaprogramming capability | ★☆☆☆☆ | No runtime code generation. Templates are static constants. |
| Macro extensibility | ★★☆☆☆ | Adding a command = add a template entry + add a handler function. Still code changes. |
| DSL creation | ★★☆☆☆ | Template bodies with `$N` markers are the DSL. Weak and positional. |
| Templates as data vs. code | ★★★★☆ | TemplateTable and OpTemplateTable are pure data constants. |

The TDD plan is a **systematic testing methodology** applied to codegen — not a new architectural vision. It would produce well-tested code, but the underlying template model remains string-based and non-homoiconic.

---

## 5. Critique of the XP Plan

**File**: [`./plans/xp_codegen_plan.md`](xp_codegen_plan.md)

### What It Gets Right

- **YAGNI — simple data structures first**: The XP plan's template format (dictionaries with `out`, `slots`, `generated_slots`) is **simple, pragmatic, and data-driven**. It doesn't over-engineer. The array-of-lines `out` format is a concrete step up from the current string-based `op_map`.

- **Incremental migration**: The XP plan's strategy of replacing one `generate_cmd_*` function at a time (6 sprints) is well-aligned with the Lisp value of **evolutionary design**. Each sprint produces working software with bit-identical output.

- **Fragment tree**: The `Fragment` data structure — a tree of resolved assembly lines with template metadata — is a step toward homoiconicity. It represents the expansion result as a structured object rather than a string.

- **`generated_slots`**: The plan explicitly models auto-generated slots (labels, temporaries) as data. This mirrors the Lisp `gensym` concept — generated symbols are declared, not scattered through code.

### What It Misses

- **No macro composition**: The XP plan's templates are flat — one template per IR command. There is no concept of composing templates (e.g., `(defmacro my-if (cond then else) ...)`) or template inheritance. The `template_table` is a dictionary, not a macro system.

- **Slot markers are string-based**: Despite the clean data structure, the slot resolution still uses `{dest}`, `{@dest}`, `{^dest}` string markers. The `SlotResolver` scans for these markers and does string substitution. No S-expressions, no quasiquote.

- **No multi-pass architecture**: The XP plan defines a linear pipeline (Slot Allocator → Pattern Matcher → Slot Resolver → Emitter), but there is no concept of **recursive expansion** — the hallmark of Lisp macro systems. In the Lisp approach, after expanding an `IF` macro, the result is itself macro-expanded. The XP plan expands once and emits.

- **`size: "auto"` is a hack**: The plan uses `"auto"` for template size, meaning "compute from sub-blocks." In a Lisp approach, size would be a derived property of the S-expression tree, not a special case.

- **No metaprogramming**: The XP plan provides no way to write functions that generate templates. The template table is a static constant.

### Summary

| Criterion | Score | Reasoning |
|-----------|:-----:|-----------|
| Homoiconicity potential | ★★★☆☆ | Fragment objects are a structural representation. Getting closer to S-expressions. |
| Code-as-data | ★★★☆☆ | Templates are dictionaries (data), but slot resolution is string-based. |
| Metaprogramming capability | ★☆☆☆☆ | No macro-generating functions. Static template table. |
| Macro extensibility | ★★★☆☆ | Adding a command = adding a template entry. YAGNI postpones complexity. |
| DSL creation | ★★☆☆☆ | Template dictionary format is a basic DSL. No embedded DSL for expansions. |
| Templates as data vs. code | ★★★★☆ | Templates are pure data dictionaries. Handlers are separate. |

The XP plan is the most **pragmatic incrementalist** approach. It shares Lisp's preference for simplicity and data-driven design, but it doesn't take the final step to full homoiconicity. The `Fragment` tree is a promising middle ground.

---

## 6. Critique of the Design Patterns (GoF) Plan

**File**: [`./plans/design_patterns_codegen_plan.md`](design_patterns_codegen_plan.md)

### What It Gets Right

- **Visitor pattern**: The Visitor pattern used for IR command dispatch (`IrCommandVisitor` with `visit_mov`, `visit_op`, etc.) is a **reasonable OOP approximation of pattern matching on sum types**. In Lisp, this would be pattern matching on S-expressions — `(match cmd ...)`. The Visitor achieves the same open-ended extensibility (adding new operations over a fixed set of types).

- **Strategy pattern for allocation**: The plan correctly identifies that register allocation and storage allocation are **pluggable strategies**. In Lisp, these would be higher-order macros or generic functions, but the Strategy pattern achieves the same separation.

- **Composite pattern**: The `AssyComponent` / `AssyBlockComposite` tree is a step toward S-expression representation. A tree of assembly instructions can be inspected, transformed, and composed — properties that Lisp S-expressions have naturally.

- **Decorator for debugging**: The `DebugTraceDecorator` and `LocationTrackingDecorator` are elegant solutions for cross-cutting concerns. In Lisp, these would be **macro-wrapping macros** — e.g., `(with-debug-trace (emit ...))`.

### What It Misses

- **OOP over-engineering**: The plan defines **30+ classes** for a single codegen module. Each IR command type gets its own class (`IrCmdMov`, `IrCmdOp`, `IrCmdIf`, ...), each with its own file. In Lisp, these would be a single sum type — `(type IrCmd (Mov dest src) (Op op a b res) (If cond res block) ...)`. The OOP approach multiplies files and boilerplate.

- **Templates are still inside code**: Despite the YAML data files, the plan puts **template loading logic** in `TemplateRegistry` and `YamlTemplateLoader` — GDScript classes that parse and validate templates. Templates are not S-expressions that can be used directly. They are data that must be processed by a dedicated engine.

- **Chain of Responsibility is overkill**: The `OperandResolver` chain (GlobalHandler, StackHandler, ImmediateHandler, RegisterHandler) is **object-oriented ceremony** around what Lisp would do with a single `match` expression:
  ```lisp
  (match (storage-type operand)
    ("global" (format "*~a" (ir-name operand)))
    ("stack"  (format "EBP[~a]" (pos operand)))
    ("immediate" (value operand)))
  ```
  Four files (handler base + 4 implementations) replaced by five lines of pattern matching.

- **No homoiconicity in template bodies**: Template bodies are still strings with `$param` markers. The `Prototype` pattern (`Template.with_params()`) is string substitution dressed in OOP clothing.

- **State pattern misunderstands macro passes**: The `CodegenState` state machine (Parsing → Allocation → Expansion → Fixup → Completed) is a **finite state machine**, not a macro pipeline. In a Lisp system, each pass is a function that transforms an S-expression. There is no global state machine — just function composition.

- **Failed to identify the core abstraction**: The GoF plan's central abstraction is the **class diagram**. The Lisp plan's central abstraction is the **macro expansion function**: `expand(sexpr, env) → sexpr`. The GoF plan has 30+ classes and 10+ patterns; the Lisp plan has 5 core functions and 5 data types.

### Summary

| Criterion | Score | Reasoning |
|-----------|:-----:|-----------|
| Homoiconicity potential | ★★★★★ | Composite and Visitor patterns enable structured representation. Closest OOP analog. |
| Code-as-data | ★☆☆☆☆ | Templates are data files (YAML), but the plan buries them under 30+ OOP classes. |
| Metaprogramming capability | ★★☆☆☆ | Template Prototype pattern enables cloning, but no runtime code generation. |
| Macro extensibility | ★★★★★ | Visitor + Strategy patterns make every axis extensible. Adding = new classes. |
| DSL creation | ★★☆☆☆ | YAML template files are a DSL. But it's buried under OOP infrastructure. |
| Templates as data vs. code | ★☆☆☆☆ | Templates are YAML data files, but they're processed by a heavy OOP engine. |

The Design Patterns plan is the **most architecturally ambitious** — and the most over-engineered. It applies 10 GoF patterns to a problem that Lisp solves with 5 functions. The irony is that the GoF patterns approximate Lisp's built-in capabilities (Visitor approximates pattern matching, Strategy approximates higher-order functions, Composite approximates S-expressions) but at 10× the code volume.

---

## 7. Critique of the Literate Programming Plan

**File**: [`./plans/literate_codegen_plan.md`](literate_codegen_plan.md)

### What It Gets Right

- **Code is data is explanation**: The Literate plan's core philosophy — that code and its documentation should be the same artifact — resonates deeply with Lisp. In Lisp, code IS data (S-expressions), and the boundary between "source" and "documentation" is naturally fluid. Literate programming formalizes this fluidity.

- **Tangling/weaving**: The tangling process (extracting code from documentation) mirrors the Lisp idea of **code generation from higher-level specifications**. The `template_defs.gd` file is "tangled" from the plan document — just as Lisp macros generate code from S-expression specifications.

- **Named slots in templates**: The plan uses `{dest}`, `{src}`, `{scope}` as named slots — a significant improvement over positional `%a`/`%b` or `$1`/`$2`. Named slots are self-documenting, which is the essence of literate programming.

- **Pipeline is explicit**: The plan's CodegenPipeline with explicit `_matcher`, `_slot_resolver`, `_emitter` mirrors the Lisp macro-pass architecture. Each component has a clear responsibility.

### What It Misses

- **Templates are still strings**: Despite the literal programming wrapping, the template bodies are arrays of strings (`"mov {dest}, {src};"`). They are not S-expressions. They cannot be pattern-matched, composed, or transformed with the same Lisp machinery used for the IR.

- **No metaprogramming**: The plan provides no way to write code that writes templates. The template table is a static `const` dictionary. In a true Lisp/literate system, you would have tangling macros — code that generates parts of the tangled output — but the plan's tangler is a simple Python script, not a macro system.

- **Fixup pass is a hack**: The plan's `FixupPass` replaces `__ENTER_`/`__LEAVE_` strings — the same approach as the current codegen. In a Lisp approach, the fixup would be an S-expression transformation, not a string substitution. The fixup reveals that the plan stopped short of full structural representation.

- **Tangler is external**: The plan's tangler (`tools/tangle.py`) is a Python script — a completely different language from the GDScript it processes. This breaks the "code is data" circle. A Lisp literate system would tangle within Lisp itself.

### Summary

| Criterion | Score | Reasoning |
|-----------|:-----:|-----------|
| Homoiconicity potential | ★★★★☆ | The tangling/weaving duality is structurally similar to homoiconicity. Code IS data. |
| Code-as-data | ★★★★★ | Template definitions are data structures (arrays, dicts) in source code. |
| Metaprogramming capability | ★☆☆☆☆ | The tangler is a separate Python script. No runtime code generation within GDScript. |
| Macro extensibility | ★★★☆☆ | Pipeline stages are composable. Adding stages is straightforward. |
| DSL creation | ★★★☆☆ | Template table format is a DSL embedded in GDScript data literals. |
| Templates as data vs. code | ★★★★★ | Templates are pure data — the entire template table is a const dictionary. |

The Literate Programming plan is the **most philosophically aligned** with Lisp — both view programs as communication with humans, not just machines. But it uses literate techniques for documentation rather than computation. The templates are still strings, and the tangler is external.

---

## 8. Critique of the Agile/Scrum Plan

**File**: [`./plans/agile_codegen_plan.md`](agile_codegen_plan.md)

### What It Gets Right

- **Incremental delivery**: The Agile plan's sprint-based delivery (Sprint 0 → Sprint 5) aligns with the Lisp tradition of **building the language bottom-up**. Each sprint delivers working, tested functionality.

- **Golden file oracle**: The plan's commitment to golden-file regression testing (A-3, E-1) provides a safety net for refactoring — essential for any macro system where transformations must preserve semantics.

- **Template schema as a deliverable**: The plan explicitly defines a template schema (A-2) before building the template engine. This aligns with the Lisp discipline of defining the data model before the macros that manipulate it.

### What It Misses

- **Process, not architecture**: The Agile plan specifies **how to manage the project** (sprints, velocity, retrospectives) but says very little about **what the codegen architecture should be**. The technical architecture section (§9) is a placeholder — "just enough architecture" — that doesn't address homoiconicity, macros, or S-expressions.

- **Template format is vague**: The template format (YAML with `$a`, `@a`, `^a` markers) is sketched but not designed. The plan's template examples look like the current `op_map` moved to YAML, with no structural improvement.

- **No macro concepts**: The entire plan mentions nothing about code-as-data, homoiconicity, or macro expansion. The template engine (B-1) is described as a "parser" that reads YAML — parsing is the opposite of homoiconicity.

- **Story point focus**: The plan spends more energy on **estimation** (story points, velocity, capacity planning) than on **design**. From a Lisp perspective, the design IS the product; the project management is secondary.

### Summary

| Criterion | Score | Reasoning |
|-----------|:-----:|-----------|
| Homoiconicity potential | ★★☆☆☆ | Template format is YAML — text-based, not structurally integrated with code. |
| Code-as-data | ★★★☆☆ | Templates are external YAML data files. Data-driven but not code-integrated. |
| Metaprogramming capability | ★☆☆☆☆ | No runtime code generation. Template engine is a parser. |
| Macro extensibility | ★★☆☆☆ | Backlog includes template editor and pluggable backends, but no macro design. |
| DSL creation | ★★☆☆☆ | YAML template format is a DSL. Minimal, positional marker-based. |
| Templates as data vs. code | ★★★☆☆ | YAML files are data, but the template body strings embed code-like markers. |

The Agile plan is a **project management wrapper** for a codegen rewrite. It doesn't contribute a new architectural vision — it structures the work of adopting one of the other technical plans.

---

## 9. Critique of the Waterfall/BDUF Plan

**File**: [`./plans/waterfall_codegen_plan.md`](waterfall_codegen_plan.md)

### What It Gets Right

- **Thorough requirements analysis**: The plan's Phase 1 (Requirements Specification) is detailed and traceable. Every function in the current codegen is catalogued with references to line numbers. This is useful as a reference document.

- **Template catalog is exhaustive**: The template specifications in §2.6 cover every ALU op, data movement pattern, and control flow construct. If you wanted to _manually_ verify that all IR→assembly mappings are covered, this catalog is the source of truth.

- **Sign-off gates**: The Waterfall plan enforces formal reviews before each phase. This prevents the "rewrite half the codegen and then change the requirements" anti-pattern.

### What It Misses

- **Completely anti-homoiconic**: The Waterfall plan is the **furthest from Lisp philosophy** of all 9 plans. Its central abstraction is the **document**, not the **data structure**. The design is described in prose, tables, and YAML schemas — none of which are executable. There is no "code is data" insight; there is "requirements are documents."

- **Template parameters are positional**: The plan uses `%a`, `%b` (or `%1`, `%2`) for template parameters — the **same convention** as the current `op_map`. No improvement in template expressiveness.

- **No macro concept**: The plan mentions "template inheritance" (§2.5.3) using `%{super}` — a string-level inheritance mechanism. This is a pale imitation of Lisp's `call-next-method` or combinatory macro composition.

- **Massive documentation overhead**: The plan specifies 25 files, ~2,150 lines of implementation, plus ~1,500 lines of documentation. In Lisp, the same codegen could be implemented in ~300 lines of S-expression transformations, with the code itself serving as documentation.

- **Frozen design**: The plan explicitly forbids changes after sign-off without CCB approval (§5.1). In a Lisp macro system, the design evolves with the code — macros are additive, not frozen.

- **Template engine is over-specified**: The `TemplateEngine` specification includes conditional expansion (`%if %then %else %end`), inheritance, and caching — all before any code is written. A Lisp approach would start with `expand(sexpr, env) → sexpr` and add features as needed.

### Summary

| Criterion | Score | Reasoning |
|-----------|:-----:|-----------|
| Homoiconicity potential | ★☆☆☆☆ | The design is in documents, not in code. No code-is-data concept. |
| Code-as-data | ★★☆☆☆ | Templates are YAML data files. But the entire approach is document-first, not code-first. |
| Metaprogramming capability | ★☆☆☆☆ | No runtime code generation. All features are designed upfront, not discovered through use. |
| Macro extensibility | ★☆☆☆☆ | CCB approval required for changes. The opposite of extensible design. |
| DSL creation | ★★☆☆☆ | YAML template format with `%param` markers is a weak, fixed DSL. |
| Templates as data vs. code | ★★☆☆☆ | Templates are data files, but they require a heavy engine to interpret. Not first-class values. |

The Waterfall/BDUF plan is the **least Lisp-compatible** of all 9 plans. It treats codegen as a construction project (specifications → design → implementation → verification) rather than as a linguistic endeavor (define the data model → write transformations → compose). Everything is specified upfront, and everything is frozen.

---

## Cross-Cutting Analysis

### Homoiconicity: The Missing Ingredient

Every plan except the Lisp plan treats templates as **strings with placeholders** rather than as **structured data**. The plans innovate around how templates are loaded (from YAML, from TSV, from code constants), how they are resolved (via string substitution, via slot binding, via emit opcodes), and how they are organized (in registries, in pipelines, in YAML files). But none of them change the fundamental fact that templates are **opaque text** at the point of expansion.

The consequences of non-homoiconic templates:

1. **No structural pattern matching**: You cannot match on the structure of a template. You cannot write a macro that transforms "all templates that start with `mov`."
2. **No template composition**: You cannot splice one template into another without string concatenation. There is no quasiquote.
3. **No template introspection**: You cannot inspect a template's structure at runtime. You cannot ask "what are the operands of this template?" without parsing its body string.
4. **No hygienic expansion**: Every plan handles label generation ad-hoc (either by passing labels as operands or by generating them in the expander). No plan has a systematic `gensym` mechanism.

### Where Each Plan Stands on the S-Expression Axis

```
Waterfall ── AoS (objects)
Agile ───── YAML text
Data-Oriented ── Flat arrays (packed)
Unix ────── Tab-separated text
Design Patterns ── OOP composites
TDD ────── Pure functions over strings
XP ─────── Fragment trees
Functional ── Pure functions over data records
Literate ──── Tangled code from documentation
───────────────────────────────────────────
Lisp ────── S-expressions (nested arrays)
```

The plans converge on **data-driven templates** (all agree that the current `op_map` is bad) but diverge on what "data" means. The Lisp position is that data must be **structured, inspectable, and composable** — properties that strings, flat arrays, and YAML files do not provide.

### What the Lisp Plan Offers That None of These Do

1. **`expand(sexpr, env) → sexpr`**: A single, recursive function that is the entire codegen. Compare with the 30-class GoF plan or the 5-stage Unix pipeline.

2. **Quasiquote/unquote**: Template construction that is **compositional by default**. You can build templates from templates without string concatenation.

3. **Multi-pass expansion**: Macro passes that transform S-expressions into S-expressions, each step bringing the representation closer to the final assembly. Every other plan has a single "expansion" step.

4. **Pattern matching as code analysis**: Since everything is S-expressions, you can write **analysis passes** that detect dead code, optimize register usage, or verify safety — all using the same pattern-matching infrastructure.

5. **Macro-generating macros**: The Lisp plan's `define_alu_family` (line 738) generates 10+ macro definitions in a single function call. No other plan has anything like this — because no other plan treats templates as first-class data that can be generated by functions.

### Conclusion

The nine plans represent a spectrum from "string-based templates moved to data files" (Agile, Waterfall, Unix) to "structural templates with limited composition" (XP, Functional, Literate) to "object-oriented encapsulation of template logic" (Design Patterns). None of them achieve full homoiconicity — none of them treat templates as S-expressions that are structurally indistinguishable from the code they generate.

The Lisp plan stands alone in its commitment to **code-as-data in practice, not just in principle**. It defines a single, recursive expansion function; it provides quasiquote for template composition; it uses multi-pass macro expansion; and it enables metaprogramming through macro-generating macros. Every other plan improves on the current codegen, but only the Lisp plan transforms the fundamental nature of the codegen from a **procedural emitter** to a **compositional macro-expander**.

The Literate Programming plan is the most philosophically aligned (it shares Lisp's view of programs as communication), the Design Patterns plan is the most structurally elaborate (it approximates S-expressions through OOP patterns), and the Functional Purity plan is the most technically compatible (it shares the pure-transformation ethos). But none of them cross the threshold into full homoiconicity — and that threshold is where the power of Lisp-style code generation begins.
