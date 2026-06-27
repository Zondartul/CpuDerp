# Unix Philosophy Opinion: Critique of 9 Codegen Plans

> **Author**: Unix Philosophy Advocate  
> **Date**: 2026-06-27  
> **Purpose**: Evaluate 9 competing codegen redesigns against the Unix principles of composability, simplicity, doing one thing well, text-stream interfaces, and pipeline architecture.

---

## Evaluation Criteria

For each plan, I score five dimensions on a scale of **–2 (antithetical) to +2 (exemplary)**:

| Criterion | Unix Meaning |
|-----------|-------------|
| **Composability** | Can stages be mixed, matched, replaced, or recombined independently? |
| **Simplicity** | Is the design minimal? Does it avoid unnecessary abstraction layers? |
| **Does One Thing Well** | Is each module/function responsible for exactly one concern? |
| **Text-Stream Interface** | Do intermediate stages communicate via text that can be piped, grepped, redirected? |
| **Pipeline Architecture** | Is there a clear data flow of filters connected in sequence? |

---

## 1. Functional Purity Plan

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Composability | +1 | Pure functions are inherently composable. `expand_template ∘ resolve_slot` is function composition. |
| Simplicity | –1 | The [`Environment`](../plans/functional_purity_codegen_plan.md:573) struct carries **11 fields** threaded through every function. That's a hidden complexity tax. |
| Does One Thing Well | +1 | `expand_template`, `_resolve_slot`, `_alloc_register` are each single-responsibility. But `AssemblyResult` conflates 6 concerns. |
| Text-Stream Interface | –2 | **No text streams exist.** All data flows through in-memory `Dictionary` values (`Environment`, `AssemblyResult`, `SymTable`). No stage can be piped through `grep`. |
| Pipeline Architecture | 0 | There is a conceptual pipeline (IR → Template → Assembly), but it's function composition, not a pipeline of filter processes. No stdout→stdin. |

**Unix Verdict**: The pure-function approach gets composability right but fundamentally misses the Unix insight that **text is the universal interface**. Every stage returns a `Dictionary` — you can't `tee` it, `grep` it, or save it to a file for debugging. The [state threading pattern](../plans/functional_purity_codegen_plan.md:587) (take `Environment`, return new `Environment`) is elegant in Haskell; in GDScript it's just passing around big mutable-ish dictionaries. **The plan would benefit from defining a text-based intermediate format** between each pure function, so stages could be tested and debugged with standard tools.

**Recommendation**: Adopt the functional approach's **immutability discipline** but apply it to text-stream stages like my [`codegen_ir2flat`](../plans/unix_philosophy_codegen_plan.md:82) format.

---

## 2. Data-Oriented Design Plan

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Composability | –1 | The [three-pass pipeline](../plans/data_oriented_codegen_plan.md:73) (Analyze → Expand → Fixup) is hard-wired. Passes share flat arrays via static variables — you cannot run a pass independently. |
| Simplicity | –1 | Structure-of-Arrays for 1000 commands saves ~120KB of memory in a **game engine**. That's optimization, not simplicity. The flat symbol table with [binary search](../plans/data_oriented_codegen_plan.md:151) is more complex than a `Dictionary`. |
| Does One Thing Well | +1 | Each of the three passes has a clear responsibility (count, expand, fixup). |
| Text-Stream Interface | –2 | **No text at all.** Everything is `PackedInt32Array`, `PackedByteArray`, `PackedStringArray`. These are binary — ungreppable, unpipable, undebuggable without custom tooling. |
| Pipeline Architecture | 0 | The [three-pass design](../plans/data_oriented_codegen_plan.md:73) is a pipeline in spirit, but passes communicate through **shared mutable static variables** ([`cmd_heads`, `reg_bitmask`, `asm_buffer`](../plans/data_oriented_codegen_plan.md:109-296)). This is the antithesis of Unix pipelines. |

**Unix Verdict**: The DOD plan optimizes for **CPU cache lines** at the cost of **human comprehension**. The [4-bit bitmask for register allocation](../plans/data_oriented_codegen_plan.md:309) is clever engineering — but it lives in a static variable, not a text stream. The [pre-compiled template bytecode](../plans/data_oriented_codegen_plan.md:220) eliminates string scanning, but introduces a custom opcode interpreter with 14 opcodes (`TEXT`, `LOAD`, `STORE`, `ADDR`, `TEMP_REG`, etc.). That's a mini-VM inside the codegen. **The Unix way would be to use text as the intermediate format and rely on the OS pipe mechanism, not build a bespoke bytecode interpreter.**

The irony: this plan's SoA layout would be **excellent** for the hot-path of a text-pipeline stage, if it accepted and produced text lines instead of sharing static arrays.

**Recommendation**: Use the DOD flat arrays as an **internal optimization** of a text-pipeline stage, not as a replacement for the pipeline itself.

---

## 3. TDD Plan

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Composability | +1 | The [dependency injection architecture](../plans/tdd_codegen_plan.md:1429) (`TemplateExpander` depends on `OperandResolver`, `AssemblyBuffer`, `RegAllocState`) makes components replaceable. |
| Simplicity | +1 | Classes like [`AssemblyBuffer`](../plans/tdd_codegen_plan.md:247) and [`RegAllocState`](../plans/tdd_codegen_plan.md:324) are small and focused. The test infrastructure enforces minimal interfaces. |
| Does One Thing Well | +1 | Each file has a single responsibility: `codegen_text.gd` for text, `codegen_register.gd` for registers, etc. |
| Text-Stream Interface | –1 | The [`AssemblyBuffer`](../plans/tdd_codegen_plan.md:247) accumulates text, but the interface between stages is **constructor injection, not text streams**. `OperandResolver.resolve_load()` returns a `String`, but this is a function call, not a pipe. |
| Pipeline Architecture | 0 | The [CodegenDriver](../plans/tdd_codegen_plan.md:1274) orchestrates stages procedurally. There's an implicit pipeline, but no explicit pipe mechanism — each stage mutates the shared `buf` and `regs` objects. |

**Unix Verdict**: The TDD plan produces the **most testable code** of any plan — and that's valuable. But testability and Unix-philosophy composability are different virtues. The test-driven approach leads to [small, focused units](../plans/tdd_codegen_plan.md:1397) that are independently verifiable, which I respect. However, the resulting architecture is **object-oriented composition, not pipeline composition**. You can't run `| codegen_expand | codegen_fixup |` in a shell because the stages communicate through injected object references, not text.

The [12 Red-Green-Refactor increments](../plans/tdd_codegen_plan.md:153) are a strength: each increment adds one capability while keeping tests green. But the final design is closer to [Smalltalk MVC](../plans/tdd_codegen_plan.md:1429) than to [the Unix pipe model](../plans/unix_philosophy_codegen_plan.md:36).

**Recommendation**: Borrow the TDD plan's **test discipline and incrementalism** — but apply it to building a text pipeline, not an object graph.

---

## 4. XP Plan

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Composability | +1 | The [four-pass pipeline](../plans/xp_codegen_plan.md:33) (Slot Alloc → Pattern Match → Slot Resolve → Emit) is cleanly separated. Passes are explicitly designed to be testable in isolation. |
| Simplicity | +1 | YAGNI-driven. The plan explicitly [defers](../plans/xp_codegen_plan.md:331) register spilling, instruction scheduling, template inheritance. This is good Unix thinking. |
| Does One Thing Well | +1 | [`SlotAllocator`](../plans/xp_codegen_plan.md:141), [`PatternMatcher`](../plans/xp_codegen_plan.md:165), [`SlotResolver`](../plans/xp_codegen_plan.md:196), [`Emitter`](../plans/xp_codegen_plan.md:221) — each has exactly one job. |
| Text-Stream Interface | –1 | The [`Fragment`](../plans/xp_codegen_plan.md:305) data structure is an object tree (`template`, `bindings`, `generated`, `resolved_lines`). It's not a text stream — you can't grep a Fragment tree. |
| Pipeline Architecture | +1 | The [pipeline diagram](../plans/xp_codegen_plan.md:33) shows data flowing left-to-right through discrete passes. The [incremental migration](../plans/xp_codegen_plan.md:238) (one IR command at a time, always green) is a model of Unix evolutionary design. |

**Unix Verdict**: The XP plan is **ideologically closest to Unix** among the non-Unix plans. It values simplicity, incrementalism, and YAGNI. The [template data structure](../plans/xp_codegen_plan.md:82) (`out` as array of lines, explicit `slots`, `generated_slots`) is a pragmatic Unix approach — templates are structured data, not opaque strings. The [six-sprint migration](../plans/xp_codegen_plan.md:238) (extract one pass per sprint, always comparing output) is exactly how a Unix craftsman would refactor: **small, reversible, verifiable steps**.

What's missing: text-stream interfaces between passes. If `PatternMatcher` wrote line-oriented text and `SlotResolver` read it, the pipeline would be Unix-perfect. Currently, passes communicate through `Fragment` objects — which is better than shared global state, but not as good as text.

**Recommendation**: Add a **line-oriented text format** for the `Fragment` intermediate representation. Then you'd have: `cat ir.yaml | slot_alloc | pattern_match | slot_resolve | emit > out.asm`.

---

## 5. Design Patterns (GoF) Plan

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Composability | –1 | The [Mediator pattern](../plans/design_patterns_codegen_plan.md:557) centralizes orchestration — components don't compose directly, they go through the mediator. |
| Simplicity | **–2** | **30+ files** for a codegen that currently fits in 1 file. Each with its own class, interface, and test. The file tree alone ([`cmd/`, `visitor/`, `template/`, `alloc/`, `emit/`, `resolve/`](../plans/design_patterns_codegen_plan.md:766)) is longer than the original codegen. |
| Does One Thing Well | +1 | Every GoF class has a single responsibility by definition. `LinearScanAllocator` does only register allocation. |
| Text-Stream Interface | **–2** | **No text anywhere.** The [Visitor pattern](../plans/design_patterns_codegen_plan.md:118) produces a `String`, but the intermediary is `IrCommand` objects with typed fields. The [Composite pattern](../plans/design_patterns_codegen_plan.md:297) builds an object tree (`AssyInstruction`, `AssyBlock`). The [Chain of Responsibility](../plans/design_patterns_codegen_plan.md:479) routes through handler objects. Every interface is an object interface. |
| Pipeline Architecture | –1 | The [Mediator pattern](../plans/design_patterns_codegen_plan.md:557) is the opposite of a pipeline — it's a central controller. The [State pattern](../plans/design_patterns_codegen_plan.md:592) models phases as state transitions, not pipe stages. |

**Unix Verdict**: This is the most **architecturally impressive and practically wasteful** plan. It applies **10 GoF patterns** to a problem that needs a few hundred lines of pipeline code. The [Visitor pattern dual dispatch](../plans/design_patterns_codegen_plan.md:164) (`cmd.accept(visitor)` → `visitor.visit_mov(cmd)`) is elegant OOP — and utterly unnecessary for a codegen where `cmd.words[0]` can dispatch to the right template via a simple `Dictionary` lookup.

The [30+ file structure](../plans/design_patterns_codegen_plan.md:766) is the Unix **"do one thing"** principle taken to absurdity: each file does one thing, but you need 30 files to do 30 things, where 5 would suffice. The [Decorator pattern](../plans/design_patterns_codegen_plan.md:343) for debug tracing is over-engineering: `if config.debug: emit_comment()` is simpler, clearer, and equally testable.

**The Unix philosophy says "simplicity over cleverness."** This plan is cleverness over simplicity.

**Recommendation**: Salvage the **Strategy pattern** for pluggable register allocation — that's genuinely useful. Throw away the rest.

---

## 6. Literate Programming Plan

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Composability | 0 | The [pipeline classes](../plans/literate_codegen_plan.md:12) (`PatternMatcher`, `SlotResolver`, `Emitter`) are separable. But composability is achieved through object composition, not text streams. |
| Simplicity | 0 | The code is simple — but the **process** is not. Literate programming requires a [tangler tool](../plans/literate_codegen_plan.md:865) to extract code from markdown. That's a tooling dependency. |
| Does One Thing Well | +1 | Each class has one job. `Emitter` emits; `SlotResolver` resolves slots; `PatternMatcher` matches patterns. |
| Text-Stream Interface | +1 | The [template table](../plans/literate_codegen_plan.md:120) is pure text data — a Dictionary of arrays and strings. The [fixup pass](../plans/literate_codegen_plan.md:760) works on text strings. These are text-friendly. |
| Pipeline Architecture | +1 | The [`generate()` function](../plans/literate_codegen_plan.md:612) is a clean pipeline: load IR → build syms → emit blocks → fixup → append globals. The [pipeline diagram](../plans/literate_codegen_plan.md:46) shows data flow clearly. |

**Unix Verdict**: The literate plan has a **well-structured pipeline** — arguably the cleanest of all 9 plans in terms of data flow. The [`PatternMatcher` → `SlotResolver` → `Emitter`](../plans/literate_codegen_plan.md:52) sequence is a real pipeline. The template table as [pure data structures](../plans/literate_codegen_plan.md:120) rather than string-replace templates is a good Unix choice.

The literate programming aspect itself is **orthogonal to Unix philosophy**. Unix cares about how programs communicate (text streams), not how they're documented. The [tangler script](../plans/literate_codegen_plan.md:865) is a Unix-filter-style tool (reads markdown, writes `.gd` files), which I appreciate.

**Criticism**: The [fixup pass](../plans/literate_codegen_plan.md:760) does string replacement on `__ENTER_`/`__LEAVE_` placeholders. My plan uses the same approach — so I can't fault it. But the literate plan doesn't go far enough: it never defines a **text-based intermediate format** between pipeline stages.

**Recommendation**: The pipeline structure is sound. Make it text-based by defining line-oriented formats for each stage's I/O.

---

## 7. Agile/Scrum Plan

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Composability | 0 | The [technical architecture](../plans/agile_codegen_plan.md:375) shows a pipeline (Deserializer → Symbol Table → Emit Engine). But the sprint structure doesn't enforce composability as a design goal. |
| Simplicity | –1 | The [sprint plan](../plans/agile_codegen_plan.md:135) is 6 sprints with 30+ stories, each with story points, owners, dependencies. That's **process complexity**, not software complexity. The process itself is heavy. |
| Does One Thing Well | 0 | The epic breakdown (Template Engine Core, Emit Engine Refactor, IR Command Migration) groups work by concern, which is sensible. But "Template Parser" + "Placeholder Resolution" + "Flat Symbol Table" in separate sprints suggests parallel work, not clean separation. |
| Text-Stream Interface | –1 | The [MVP template format](../plans/agile_codegen_plan.md:396) uses `$a`, `$b` marker syntax — opaque string markers in a YAML file. No mention of text-stream interfaces between pipeline stages. |
| Pipeline Architecture | –1 | The [high-level pipeline diagram](../plans/agile_codegen_plan.md:376) shows one arrow (IR → Deserializer → Symbol Table → Emit Engine → Assembly). That's not a **pipeline of filters**; it's a **sequence of steps** inside a single process. |

**Unix Verdict**: The Agile plan is focused on **project management**, not software architecture. The 12-week sprint plan with velocity tracking, story points, and retrospectives is a process concern, not a technical one. The [Definition of Done](../plans/agile_codegen_plan.md:113) (code review, 80% coverage, golden files) is good engineering practice that any approach should adopt.

But the technical architecture takes a back seat. The [template format](../plans/agile_codegen_plan.md:396) uses `$` markers embedded in strings — the same anti-pattern as the current `op_map`. The [emit bytecode](../plans/agile_codegen_plan.md:443) (`TemplateOp`) is a mini-VM, not a Unix filter.

**The Unix lesson**: The plan that spends 6 sprints planning _how_ to build is missing _what_ to build. A Unix approach would be: **write the first filter today, pipe it tomorrow, finish the pipeline by next week**.

**Recommendation**: The sprint structure and golden file regression suite are good project practices. The technical architecture needs a fundamental rethink toward text pipelines.

---

## 8. Waterfall/BDUF Plan

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Composability | –1 | The [5-stage pipeline](../plans/waterfall_codegen_plan.md:276) is locked at design time. You cannot reorder, insert, or remove stages without a [Change Request](../plans/waterfall_codegen_plan.md:1613) through the **Change Control Board**. |
| Simplicity | **–2** | **5 phases** (Requirements, Architecture, Implementation, Verification, Maintenance) with **formal sign-offs** at each gate. The design specification alone is [60 person-hours](../plans/waterfall_codegen_plan.md:265). The [Requirements Traceability Matrix](../plans/waterfall_codegen_plan.md:228) tracks 25+ requirements across 22 files. |
| Does One Thing Well | +1 | Each [component specification](../plans/waterfall_codegen_plan.md:356) is detailed and single-purpose. `RegisterAllocator` allocates registers; `ControlFlowHandler` handles branches. |
| Text-Stream Interface | –2 | The [Template schema](../plans/waterfall_codegen_plan.md:186) uses YAML with `%param` substitution — embedded in a `template_engine` that resolves them via string replacement. The pipeline stages communicate through in-memory objects (`AssyBlock`, `ErrorReport`, `CommandDescriptor`). |
| Pipeline Architecture | 0 | The [pipeline diagram](../plans/waterfall_codegen_plan.md:277) shows 5 discrete stages. But the pipeline is **designed up-front and frozen**. You can't evolve it through use. |

**Unix Verdict**: This is the **anti-Unix plan**. Every Unix principle is inverted:

- **Simplicity** → 22 files, 5 phases, 4 sign-offs, a Change Control Board.
- **Do one thing well** → The plan does one thing (specify everything) but does it so thoroughly that it can't adapt.
- **Text streams** → Every interface is a custom object type (`ErrorReport`, `CommandDescriptor`, `TemplateResult`). No text, no pipes.
- **Pipeline** → The pipeline is locked at design time. The [Design Review Checklist](../plans/waterfall_codegen_plan.md:1280) has 10 items that must pass before implementation begins.
- **Composability** → Composability requires the ability to swap components. The Waterfall plan forbids changes after Phase 2 sign-off.

The [template inheritance feature](../plans/waterfall_codegen_plan.md:701) (`extends: <parent>`) is over-engineering: it's a solution to a problem the current codegen doesn't have. The [conditional expansion](../plans/waterfall_codegen_plan.md:690) (`%if <param> %then ... %else ... %end`) adds a mini-language embedded in template strings.

**The irony**: the most rigorously specified plan produces the most brittle design. Ken Thompson would shake his head.

**Recommendation**: Salvage the **test case catalog** (30+ specific test cases in §4.2) — that level of testing detail is valuable. Ignore the rest of the process.

---

## 9. Lisp/Macro Plan

| Criterion | Score | Rationale |
|-----------|-------|-----------|
| Composability | +1 | [Macro passes](../plans/lisp_macro_codegen_plan.md:345) are composable by design: each pass transforms S-expressions → S-expressions. You can add, remove, or reorder passes freely. |
| Simplicity | –1 | The plan introduces [5 new classes](../plans/lisp_macro_codegen_plan.md:493) (`MacroEngine`, `MacroPass`, `MacroEnvironment`, `PatternVar`, `QQUnquote`), a [quasiquote DSL](../plans/lisp_macro_codegen_plan.md:107), and a [14-opcode bytecode](../plans/lisp_macro_codegen_plan.md:221) — all to replace what is fundamentally a text transformation. |
| Does One Thing Well | +1 | Each macro pass does one thing: `register-allocation-pass`, `label-resolution-pass`, `serialization-pass`. |
| Text-Stream Interface | –1 | S-expressions are nested arrays — **structured data, not text**. You can't grep an S-expression tree. However, the [serialization pass](../plans/lisp_macro_codegen_plan.md:440) turns sexprs into text at the end, so the final output is text-friendly. |
| Pipeline Architecture | **+2** | The [pipeline composition](../plans/lisp_macro_codegen_plan.md:464) is superb: `var pipeline = [template_expansion, storage_alloc, reg_alloc, label_resolve, serialize]`. Each pass is a filter: `pass.process(asm_sexpr, env) → asm_sexpr`. This is the closest any plan comes to a true Unix pipeline. |

**Unix Verdict**: The Lisp plan has the **best pipeline architecture** of all 9 plans. The [macro pass composition](../plans/lisp_macro_codegen_plan.md:456) is a genuine filter pipeline: each pass transforms a representation, the output of one is the input of the next. The [fixpoint expansion](../plans/lisp_macro_codegen_plan.md:514) (`expand until stable`) is a powerful concept.

But the plan is **over-engineered for GDScript**. Lisp macros are elegant in Lisp because the language is homoiconic — code IS data. GDScript is not homoiconic. The [quasiquote DSL](../plans/lisp_macro_codegen_plan.md:109) (`["quasiquote", ["mov", ["unquote", "dest"], ["unquote", "src"]]]`) is a leaky abstraction: you're simulating Lisp in a language that doesn't support it.

The [macro-generating macro `define_alu_family`](../plans/lisp_macro_codegen_plan.md:738) is genuinely elegant — it eliminates 10+ repetitive template definitions in one call. That's the Unix principle of **"write programs that generate programs"** (one of the original Unix philosophies).

**Recommendation**: Adopt the **macro pass pipeline architecture** — it's the best pipeline design of all 9 plans. Replace the S-expression intermediate representation with **text lines** (to get grepability). Keep the `define_alu_family` metaprogramming approach.

---

## Summary Table

| Plan | Composability | Simplicity | One Thing Well | Text Stream | Pipeline | **Total** |
|------|:---:|:---:|:---:|:---:|:---:|:---:|
| **Unix (my plan)** | +2 | +2 | +2 | +2 | +2 | **+10** |
| Functional Purity | +1 | –1 | +1 | –2 | 0 | **–1** |
| Data-Oriented Design | –1 | –1 | +1 | –2 | 0 | **–3** |
| TDD | +1 | +1 | +1 | –1 | 0 | **+2** |
| XP | +1 | +1 | +1 | –1 | +1 | **+3** |
| Design Patterns (GoF) | –1 | –2 | +1 | –2 | –1 | **–5** |
| Literate Programming | 0 | 0 | +1 | +1 | +1 | **+3** |
| Agile/Scrum | 0 | –1 | 0 | –1 | –1 | **–3** |
| Waterfall/BDUF | –1 | –2 | +1 | –2 | 0 | **–4** |
| Lisp/Macro | +1 | –1 | +1 | –1 | **+2** | **+2** |

---

## Key Takeaways

### What Unix Can Learn From Each Plan

1. **Functional Purity** — State threading (Environment → new Environment) is over-engineered for GDScript, but the principle of **immutable intermediate values** is sound. My pipeline can adopt this: each stage takes input text, returns output text, with no side effects.

2. **Data-Oriented Design** — The [pre-compiled template bytecode](../plans/data_oriented_codegen_plan.md:220) eliminates string scanning at emit time. My plan currently uses a template TSV lookup — I could pre-compile those TSV entries into a flat array indexed by opcode ID for faster dispatch.

3. **TDD** — The [incremental Red-Green-Refactor discipline](../plans/tdd_codegen_plan.md:153) is excellent practice. My pipeline stages should be built test-first: write a flat-IR test case, implement the stage, verify output.

4. **XP** — The [incremental migration strategy](../plans/xp_codegen_plan.md:238) (one IR command at a time, always green) is the safest way to replace 833 lines of working code. My plan should adopt this explicitly.

5. **Literate Programming** — The pipeline architecture in the literate plan is clean. Their [`CodegenPipeline.generate()`](../plans/literate_codegen_plan.md:612) is a well-structured orchestration that my pipeline orchestrator should emulate.

6. **Lisp/Macro** — The [macro pass pipeline](../plans/lisp_macro_codegen_plan.md:464) (`var pipeline = [...]`) is the most elegant pipeline composition of any plan. My plan should define stages as a list of filter functions, not hard-coded sequential calls.

7. **Agile/Scrum** — The [golden file regression suite](../plans/agile_codegen_plan.md:1000) (`test_codegen_oracle.gd`) is essential. My plan needs an automated test that compares pipeline output against saved expected output.

8. **Waterfall** — The [test case catalog](../plans/waterfall_codegen_plan.md:1483) (30+ specific test cases) is thorough. My plan should specify test cases at this level of detail.

9. **Design Patterns** — The [Strategy pattern for register allocation](../plans/design_patterns_codegen_plan.md:179) is genuinely useful. My plan's `reg_resolve` stage should accept a pluggable allocator strategy.

### The One Universal Agreement

**All 9 plans agree** that the current [`codegen_md.gd`](../scenes/codegen_md.gd) (833 lines) is a monolithic problem that needs to be broken apart. The disagreement is about the mechanism:

- OOP plans break it into **classes** (GoF, TDD, XP)
- Data plans break it into **arrays** (DOD)
- Function plans break it into **pure functions** (Functional Purity)
- Process plans break it into **sprints** (Agile, Waterfall)
- Macro plans break it into **passes** (Lisp)
- Documentation plans break it into **code blocks** (Literate)
- **Unix breaks it into filters**

The Unix approach is the only one where the communication between parts is a **universal, debuggable, pipable format** (text). Every other plan creates custom inter-component interfaces that can't be inspected with standard tools.

### Final Unix Verdict on Each Plan

| Plan | Verdict |
|------|---------|
| **Functional Purity** | Good ideas (immutability, pure functions), wrong interface (Dictionaries instead of text). |
| **Data-Oriented Design** | Premature optimization for a game engine codegen. Elegant bitmask allocator wasted on a non-cache-bound problem. |
| **TDD** | Best testing discipline of all plans. The resulting architecture is too object-oriented for my taste, but the tests are worth adopting. |
| **XP** | Closest to Unix in spirit. Incremental, simple, YAGNI-focused. Needs text-stream interfaces. |
| **Design Patterns** | Worst plan for this problem. 30+ files to do what 5 pipeline stages can do. Architectural over-engineering. |
| **Literate Programming** | Clean pipeline, unnecessary tooling overhead. The tangler is a nice Unix tool in spirit. |
| **Agile/Scrum** | Process over product. Good project management, weak technical architecture. |
| **Waterfall/BDUF** | Anti-Unix. Bureaucratic, frozen, change-resistant. The test catalog is the only salvageable part. |
| **Lisp/Macro** | Best pipeline architecture, best composability, best metaprogramming. Over-engineered for GDScript's capabilities. |

---

*"This is the Unix philosophy: Write programs that do one thing and do it well. Write programs to work together. Write programs to handle text streams, because that is a universal interface."* — Doug McIlroy
