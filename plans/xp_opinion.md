# XP Advocate's Opinion: Critique of All Codegen Plans

**Author**: Extreme Programming Advocate  
**Evaluated against**: Simplicity (YAGNI), Incremental Delivery, Team Ownership, Courage to Refactor, Speed to Working Software  
**Reading guide**: Each plan is scored on a scale from **✔️ Strong** (aligned with XP) to **❌ Anti-XP**. Constructive critique follows each score.

---

## 1. Functional Purity Advocate — [`functional_purity_codegen_plan.md`](functional_purity_codegen_plan.md)

| Criterion | Verdict |
|---|---|
| Simplicity (YAGNI) | ❌ **Over-engineered** |
| Incremental Delivery | ❌ **Big-bang purity conversion** |
| Team Ownership | ❌ **High barrier to entry** |
| Courage to Refactor | ✔️ **Correct diagnosis of state problems** |
| Speed to Working Software | ❌ **Delayed by infrastructure** |

### Critique

The Functional Purity plan makes an **excellent diagnosis** of the current codegen's problems — mutable globals, side-effectful `emit`, non-reentrant state. The table of purity violations ([`functional_purity_codegen_plan.md:13-24`](functional_purity_codegen_plan.md:13)) is spot-on.

**However**, the proposed solution is **antithetical to XP**. The plan demands that **every function be pure from Day 1**. Look at [`AssemblyResult`](functional_purity_codegen_plan.md:145-152): it's a Dictionary with seven fields including `reg_alloc: RegAllocState` that itself contains a `regs_in_use` Dictionary that must be **immutably copied on every transition**. This is an enormous amount of scaffolding to build before delivering any value.

**The YAGNI problem**: The plan introduces algebraic sum types (`Template` with `"type"` variant tags), `SlotSpec` with type filters, `SymTable` as an immutable snapshot — all before a single line of assembly is emitted differently. XP asks: *"What's the simplest thing that could possibly work?"* For the current codegen, the simplest thing is to extract the template table as data (a Dictionary of Dicts), not build an entire type-safe functional runtime.

**The incremental delivery problem**: The plan describes a single `compile_program` function (line 187) that replaces the entire pipeline. There's no migration strategy — no "replace one `generate_cmd_*` at a time." It's a **big-bang rewrite** with a purity constraint, which means weeks of work before any integration test passes.

**Team ownership**: Requiring every contributor to write pure functions with explicit state threading in GDScript (a language that encourages mutation) is a **high cognitive tax**. New team members would struggle to add a simple template.

**Constructive suggestion**: XP agrees with the goal of eliminating mutable globals, but would do it incrementally: first extract the template table as data (no purity required), then extract `SlotAllocator` as a pure-ish pass, *then* make individual functions pure as a refactoring step — not as a prerequisite.

---

## 2. Data-Oriented Design Advocate — [`data_oriented_codegen_plan.md`](data_oriented_codegen_plan.md)

| Criterion | Verdict |
|---|---|
| Simplicity (YAGNI) | ❌ **Premature optimization** |
| Incremental Delivery | ❌ **Massive data model migration** |
| Team Ownership | ❌ **Maintenance nightmare** |
| Courage to Refactor | ❌ **Static arrays resist change** |
| Speed to Working Software | ❌ **Months before first output** |

### Critique

This plan is the **furthest from XP** of all nine. It proposes replacing Godot Dictionaries with **seven parallel `PackedInt32Array`s** for the symbol table alone ([`data_oriented_codegen_plan.md:136-153`](data_oriented_codegen_plan.md:136)), a flat IR command table with `cmd_heads`, `cmd_operand_offset`, `cmd_operand_count`, `cmd_loc_begin`, `cmd_loc_end` arrays ([line 116-120](data_oriented_codegen_plan.md:116)), and a template engine that compiles templates into **bytecode opcodes** with a custom interpreter ([line 226-241](data_oriented_codegen_plan.md:226)).

**The YAGNI problem is acute**: The plan optimizes for CPU cache line utilization in a **GDScript codegen** that processes maybe hundreds of IR commands per compilation. GDScript itself is an interpreted language running on Godot's VM — the overhead of the interpreter dwarfs any cache-miss savings from `PackedInt32Array` vs Dictionary. The plan is effectively optimizing at the wrong level of abstraction for the wrong platform.

**The incremental delivery problem**: You cannot migrate one IR command at a time to this architecture. The entire IR representation must be converted from object-graph to SoA *before the first template works*. This is a **big-bang data migration** of the entire compiler frontend.

**Courage to refactor**: With `static` arrays at module scope, every pass is coupled to global state. XP values **collective ownership** and **fearless refactoring**. Global `static` arrays resist refactoring — you can't have two independent codegen pipelines, you can't test a pass in isolation without resetting global arrays, and you can't easily add a new field without modifying every parallel array.

**Team ownership**: Who wants to maintain `sym_ir_name[lookup[sym_hash(name)]]` instead of `all_syms[name]`? The readability cost alone kills team velocity.

**Constructive suggestion**: The **three-pass pipeline** concept (Analyze & Alloc → Template Expansion → Fixup & Link) is actually sound from an XP perspective. XP would keep the passes but use **simple Dictionaries and Arrays** — not `PackedInt32Array` — and deliver the first pass working before designing the second. The **4-bit bitmask** for register allocation ([line 309-317](data_oriented_codegen_plan.md:309)) is a genuinely good, simple idea that XP would adopt immediately. The rest is YAGNI.

---

## 3. Unix Philosophy Advocate — [`unix_philosophy_codegen_plan.md`](unix_philosophy_codegen_plan.md)

| Criterion | Verdict |
|---|---|
| Simplicity (YAGNI) | ✔️ **Simple pipeline concept** |
| Incremental Delivery | ✔️ **Stage isolation enables increments** |
| Team Ownership | ⚠️ **Mixed — text streams help, 5 stages hurt** |
| Courage to Refactor | ✔️ **Stages are replaceable** |
| Speed to Working Software | ⚠️ **Over-partitioned into 5 stages** |

### Critique

This plan has the **most XP-compatible architecture** of all nine. The pipeline of small text filters ([`unix_philosophy_codegen_plan.md:68-78`](unix_philosophy_codegen_plan.md:68)) — `ir2flat → sym_alloc → templ_expand → reg_resolve → line_asm` — embodies the Unix principle "do one thing and do it well", which closely mirrors XP's **simplicity** and **single responsibility**.

**The template-as-data-file idea** ([line 138-146](unix_philosophy_codegen_plan.md:138)) using TSV files is beautiful in its simplicity. A TSV file can be edited by anyone, version-controlled, and grep'd. This aligns perfectly with XP's **collective ownership** — the language designer doesn't need to write GDScript to add an instruction.

**However, 5 stages is too many for an initial increment**. XP would ask: "What's the simplest pipeline that delivers working software?" The answer is **2 stages**: (1) a template expander that reads templates from a data file, (2) an emitter that produces text. The symbol allocation, register resolution, and line assembly can be folded into these two stages initially and **extracted later when the need for separation becomes painful**.

**The text-stream interface** is elegant but introduces serialization/deserialization overhead for each stage. In a Godot process, this means converting Arrays ↔ tab-separated strings ↔ Arrays at every boundary. XP would prefer **function calls with simple data structures** (Dictionaries, Arrays) between stages, keeping the *interface* stable but avoiding the text overhead. The text-stream concept can be layered on later if needed (e.g., for debugging or external tooling).

**Team ownership**: The plan's TSV template file is excellent for team ownership. The `sym_alloc` and `reg_resolve` stages being standalone scripts that can be tested independently is also good. But 5 separate `.gd` files, each with its own I/O format, creates more coordination surface than XP would like for a 2-developer team.

**Constructive suggestion**: XP endorses this plan's **direction** but would collapse to 2-3 stages initially: a `TemplateExpander` (reads TSV templates, matches IR commands) and an `Emitter` (handles registers, addresses, and output). Extract more stages only when a clear need emerges (e.g., when register allocation becomes complex enough to justify its own test suite).

---

## 4. TDD Advocate — [`tdd_codegen_plan.md`](tdd_codegen_plan.md)

| Criterion | Verdict |
|---|---|
| Simplicity (YAGNI) | ✔️ **Test-driven = simple by construction** |
| Incremental Delivery | ✔️ **12 increments, each green before next** |
| Team Ownership | ✔️ **Tests as specification** |
| Courage to Refactor | ✔️ **Safety net enables refactoring** |
| Speed to Working Software | ⚠️ **Slow start (test infrastructure first)** |

### Critique

This plan is the **closest ally to XP**. The TDD Advocate and the XP Advocate share almost identical values: incremental delivery (Red-Green-Refactor), test-first design, simple solutions, and confidence to refactor.

**The 12-increment plan** ([`tdd_codegen_plan.md:151-155`](tdd_codegen_plan.md:151)) is exactly what XP prescribes: start with the simplest possible codegen case (`MOV`), get it tested and green, then add complexity incrementally. Each increment builds on tested foundations.

**The test infrastructure** (Increment 0, [`line 155-198`](tdd_codegen_plan.md:155)) is a point of mild disagreement. XP would say: "Write the first test for `MOV` first, and build just enough infrastructure to run *that* test." The TDD plan pre-builds an entire test directory with 7 test files, fixtures, and a custom runner before any production code. XP prefers to evolve the test infrastructure alongside the production code — if you only need 3 test assertions for `MOV`, you don't need a `test_runner.gd` yet.

**The architecture** (Layers 0-5, [`line 86-113`](tdd_codegen_plan.md:86)) is clean and well-separated. The `AssemblyBuffer` with `append_with_size` and `mark_location` is a good example of **simple, testable design**.

**Courage to refactor**: The test suite gives the team courage, but the plan doesn't explicitly address **incremental migration of the existing codebase**. It describes building a *new* codegen from scratch with tests, then presumably replacing the old one. XP would prefer to **test-harness the existing codegen** first (characterization tests), then refactor incrementally, keeping tests green at every step.

**Constructive suggestion**: XP fully endorses this plan but would:
1. Add characterization tests for the *existing* [`codegen_md.gd`](../scenes/codegen_md.gd) before writing any new code
2. Build the test infrastructure **on demand** (one test file at a time, not all 7 upfront)
3. Replace one `generate_cmd_*` at a time using the new template engine, not build the entire engine offline

---

## 5. Design Patterns (GoF) Advocate — [`design_patterns_codegen_plan.md`](design_patterns_codegen_plan.md)

| Criterion | Verdict |
|---|---|
| Simplicity (YAGNI) | ❌ **Pattern injection** |
| Incremental Delivery | ❌ **All patterns needed at once** |
| Team Ownership | ❌ **Godot OOP overhead** |
| Courage to Refactor | ❌ **Rigid interfaces** |
| Speed to Working Software | ❌ **Class hierarchy before value** |

### Critique

This plan is an **textbook case of over-engineering from an XP perspective**. It applies six GoF patterns (Command, Visitor, Strategy, Template Method, Composite, Decorator, Prototype) to what is fundamentally a **data-transformation problem**.

**The Visitor pattern** ([`design_patterns_codegen_plan.md:118-177`](design_patterns_codegen_plan.md:118)) is Exhibit A. It creates an `IrCommandVisitor` interface with 13 `visit_*` methods, 13 concrete `IrCommand` subclasses (`IrCmdMov`, `IrCmdOp`, etc.), and a `AssemblyEmitterVisitor` that implements all of them. This is **~26 new files/classes** to replace a 13-line `match` statement. XP asks: "Does this make the system easier to change?" The answer is **no** — adding a new opcode now requires 4 files (command class, visitor interface method, visitor implementation, template registry entry) instead of 2 (a `match` branch and a template table entry).

**The Strategy pattern** for register allocation ([line 187-233](design_patterns_codegen_plan.md:187)) is YAGNI: the codegen will never need more than one register allocator. A 4-element array or 4-bit bitmask is all that's needed. Abstracting it behind an interface with `LinearScanAllocator`, `GraphColoringAlloc`, and `NoAllocationStub` is waste.

**The Composite pattern** ([line 299-324](design_patterns_codegen_plan.md:299)) builds an entire tree structure for assembly blocks — `AssyInstruction` leaves, `AssyBlock` composites, visitor traversal — when the actual need is a flat string with a position counter.

**Incremental delivery**: These patterns are interdependent. You can't build the Visitor without the Command subclasses, and you can't build the Strategy without the interfaces, and you can't test anything without all of them wired together. This is a **big-bang pattern injection**.

**Team ownership**: GDScript doesn't enforce abstract interfaces at runtime. The pattern overhead makes the codebase **harder to navigate** for team members who aren't GoF scholars.

**Constructive suggestion**: XP would accept exactly **one** pattern from this plan — the **Template Registry** (which is really just a data structure, not a pattern). The Command and Visitor hierarchies should be replaced with a data-driven `template_table` Dictionary (as our own XP plan proposes). The Strategy interfaces should stay as simple function references or duck-typed objects, not abstract base classes. **Evolve the design, don't inject patterns.**

---

## 6. Literate Programming Advocate — [`literate_codegen_plan.md`](literate_codegen_plan.md)

| Criterion | Verdict |
|---|---|
| Simplicity (YAGNI) | ⚠️ **Documentation-first is good, tangle/weave is not** |
| Incremental Delivery | ✔️ **Documentation can evolve incrementally** |
| Team Ownership | ⚠️ **Documentation helps, tangle toolchain hurts** |
| Courage to Refactor | ⚠️ **Documentation drift risk** |
| Speed to Working Software | ❌ **Tangling delays delivery** |

### Critique

The Literate Programming plan has a **noble goal** (programs written for humans first) and its architecture (pipeline, template table, slot resolver) is reasonable — very similar to the XP plan's architecture. The template data structure ([`literate_codegen_plan.md:108-200`](literate_codegen_plan.md:108)) with `pattern`, `assembly`, `size`, `slots`, and `guard` fields is clean and data-driven.

**Where XP disagrees**: The **tangle/weave workflow**. The plan assumes a literate programming tool that extracts code from Markdown documentation. This introduces:
1. A **build-time dependency** (the tangle tool) that must be maintained
2. A **two-source-of-truth problem**: the Markdown document IS the source, but developers will inevitably edit the extracted `.gd` files directly, causing drift
3. A **debugging indirection**: stack traces point to extracted `.gd` files, but the source of truth is the Markdown — developers must mentally map between them

**Simplicity (YAGNI)**: The tangle/weave process adds complexity that doesn't directly improve the codegen. XP values **working software** over comprehensive documentation. The *architecture* articulated in the literate document is valuable; the *tooling* to embed code in documentation is not.

**Incremental delivery**: The plan itself can be written incrementally, but the **tangled output** cannot be partially deployed — you either have the tangle tool working with the full pipeline document, or you don't.

**Team ownership**: The prose documentation is excellent for onboarding and collective understanding. But requiring all team members to use a literate programming workflow is a barrier. XP prefers **code that is self-documenting** (simple functions, clear names, data-driven design) over external documentation that can drift.

**Courage to refactor**: Literate programming **discourages refactoring** because changing code means updating the surrounding prose. In XP, refactoring is a continuous, low-friction activity. If every code change requires rewriting paragraphs of documentation, the team will refactor less.

**Constructive suggestion**: XP endorses writing a **design document** (like this one!) that explains the architecture in prose. But the **source of truth should be the code files**, not a tangled document. Use the design document as a **living specification** that evolves alongside the code, updated *after* refactoring, not as the compilation source.

---

## 7. Agile/Scrum Advocate — [`agile_codegen_plan.md`](agile_codegen_plan.md)

| Criterion | Verdict |
|---|---|
| Simplicity (YAGNI) | ⚠️ **Process-heavy, but architecture is lean** |
| Incremental Delivery | ✔️ **Well-structured sprints** |
| Team Ownership | ✔️ **Strong team focus** |
| Courage to Refactor | ⚠️ **Process overhead may slow refactoring** |
| Speed to Working Software | ✔️ **Sprint 0 delivers a test oracle** |

### Critique

The Agile/Scrum plan is **the most organizationally aligned with XP**, though they differ in ceremony. The plan's **Epic-to-Story breakdown** ([`agile_codegen_plan.md:50-108`](agile_codegen_plan.md:50)) is well-structured: Epic A (foundation), B (template engine core), C (emit engine), D (migration), E (validation).

**Sprint 0** ([line 135-158](agile_codegen_plan.md:135)) is excellent: characterize the current system, build a test oracle, define the template schema, agree on Definition of Done. XP would call this "creating a safety net" and it's essential for courageous refactoring.

**The Definition of Done** ([line 113-122](agile_codegen_plan.md:113)) is thorough: code review, golden file pass, unit tests ≥80%, no linter warnings, documentation updated, backward compatible. XP approves.

**Where XP diverges**:

1. **Ceremony overhead**: The plan includes Sprint Planning (2h), Daily Stand-up (15min), Sprint Review (1h), Retrospective (1h) per sprint. For a 2-developer team, this is **too much process**. XP uses **stand-up meetings** but keeps planning and review lightweight — sometimes just a conversation at the whiteboard.

2. **Story points and velocity tracking** ([line 129-131](agile_codegen_plan.md:129)): XP prefers **real velocity** (actual completion rate) over estimated velocity. The plan assumes 15-20 points per sprint, but this is a guess. XP would start the first sprint, measure actual throughput, and adjust.

3. **Epic C — Emit Engine Refactor** ([line 73-81](agile_codegen_plan.md:73)) includes "Pre-compiled Template Bytecode" (C-3, 8 points) and "Buffered Assembly Output" (C-4, 5 points). These are **YAGNI** — the string-based emit works and isn't a performance bottleneck. XP would defer these to the backlog.

**Sprint structure**: The plan's sprints are **dependency-sequenced** rather than **value-sequenced**. Sprint 0 delivers infrastructure but **no working software** (no assembly output). XP would structure Sprint 0 to produce at least a working `MOV` instruction through the new pipeline, even if it's a prototype. **Working software is the primary measure of progress.**

**Constructive suggestion**: Adopt the **Epic A characterization + golden file oracle** approach (it's brilliant and XP-aligned). Collapse Sprint 0 and Sprint 1 so that by the end of the first 2 weeks, the team has a **working template-driven `MOV` instruction** AND the golden file oracle. Drop story points in favor of **simple count of migrated instructions**. Drop the Scrum ceremonies in favor of XP's lighter **stand-up + pair programming** model.

---

## 8. Waterfall/BDUF Advocate — [`waterfall_codegen_plan.md`](waterfall_codegen_plan.md)

| Criterion | Verdict |
|---|---|
| Simplicity (YAGNI) | ❌ **Massive speculation** |
| Incremental Delivery | ❌ **Deliver nothing until Phase 3** |
| Team Ownership | ❌ **Sign-off gates block contribution** |
| Courage to Refactor | ❌ **Design frozen before coding begins** |
| Speed to Working Software | ❌ **~6 months to first output** |

### Critique

This plan is **anathema to XP**. It represents everything Extreme Programming was created to rebel against.

**Phase 1** ([`waterfall_codegen_plan.md:58-186`](waterfall_codegen_plan.md:58)) is a 40-person-hour Requirements Specification with 50+ functional requirements, non-functional requirements, interface requirements, and a Requirements Traceability Matrix. All of this is **speculative** — written before a single line of code is changed.

**Phase 2** ([line 186+](waterfall_codegen_plan.md:186)) is a 1,700-line Design Specification with a complete Template Catalog, Data Dictionary, and Design Review Checklist. This is **Big Design Up Front** at its most extreme.

**The sign-off gates** (end of each phase: "Sign-Off") are anti-XP. They prevent the team from responding to feedback. If we discover during implementation that the template schema needs to change, we can't — it's signed off. XP embraces **requirements change as a competitive advantage**.

**Simplicity (YAGNI)**: The plan specifies **template inheritance** (FR-01c), **conditional expansion** (FR-01d), **runtime template reloading** (FR-01e), **multi-phase command expansion** (FR-02c), and a **plugable register allocator** (FR-03c). None of these exist in the current codegen, and none are needed for the migration. They are pure speculation.

**Incremental delivery**: The plan delivers **nothing** until Phase 3 (Implementation), which doesn't start until all requirements and design are signed off. This means **months of work with zero feedback**.

**Team ownership**: The Waterfall model is top-down. The "Change Control Board" ([line 5](waterfall_codegen_plan.md:5)) centralizes decision-making. XP's **collective ownership** means *any* developer can improve *any* part of the system. Under Waterfall, a developer can't even change a template without board approval.

**Courage to refactor**: Under Waterfall, you **can't refactor** — the design is frozen. The whole point of the plan is to get the design right *before* coding so that refactoring is unnecessary. XP knows this is a fantasy: **you cannot get the design right without building it and learning from feedback**.

**Constructive suggestion**: XP would take the **Requirements Traceability Matrix** (useful as a checklist) and the **Template Catalog** (useful as data), and throw away the rest. The **actual implementation** should start immediately — write a template for `MOV`, get it working, show it to a stakeholder, iterate. The entire 1,700-line document should be replaced with a **2-page design sketch** and a **working prototype** that takes 2 days to build.

---

## 9. Lisp/Macro-Driven Advocate — [`lisp_macro_codegen_plan.md`](lisp_macro_codegen_plan.md)

| Criterion | Verdict |
|---|---|
| Simplicity (YAGNI) | ❌ **Homoiconicity in GDScript?** |
| Incremental Delivery | ⚠️ **Layered architecture helps** |
| Team Ownership | ❌ **Unfamiliar paradigm** |
| Courage to Refactor | ❌ **DSL itself resists change** |
| Speed to Working Software | ❌ **Must build macro engine first** |

### Critique

The Lisp Macro plan is **intellectually fascinating but practically disastrous** for a GDScript codebase.

**The core insight** — that templates are macro expansion rules and should be data, not code — is sound and aligns with XP's data-driven philosophy. The bottom-up layering ([`lisp_macro_codegen_plan.md:65-105`](lisp_macro_codegen_plan.md:65)) (Layer 0: S-expressions → Layer 1: macro expansion engine → Layer 2: template table → Layer 3: macro passes → Layer 4: driver) mirrors XP's **evolutionary design**.

**The fatal problem**: GDScript does not have macros, quasiquotation, or pattern matching. The plan must **reimplement all of this** — a quasiquote expander ([line 189-200](lisp_macro_codegen_plan.md:189)), a pattern matcher ([line 156-185](lisp_macro_codegen_plan.md:156)), a macro expansion engine ([line 128-150](lisp_macro_codegen_plan.md:128)) — before any IR instruction can be compiled. This is **building a Lisp inside Godot** to solve a problem that a Dictionary lookup solves.

**Simplicity (YAGNI)**: The plan introduces `PatternVar` with type constraint callables, `QQUnquote`, quasiquote/backtick semantics, recursive macro expansion, and an environment threading system. All of this is overhead for what is fundamentally: given an IR command name, look up a template string, substitute operands.

**Team ownership**: Who on a Godot game-dev team knows Lisp macro semantics? The plan requires the entire team to understand quasiquotation, unquote-splicing, pattern variables, and macro expansion ordering. This is a **career-limiting learning curve** for most GDScript developers.

**Layered delivery**: The plan's Layer 0 → Layer 1 → Layer 2 structure does enable incremental delivery *within the macro paradigm*, but the paradigm itself is so unfamiliar that each layer takes much longer than a simple equivalent in imperative GDScript.

**Courage to refactor**: The macro table is data (good), but the macro *engine* is a complex recursive tree-walker with mutable environment. Refactoring the engine (e.g., adding macro cacheing, debugging support, or error reporting) requires deep understanding of the expansion algorithm.

**Constructive suggestion**: XP would adopt the **template table as data** concept (Layer 2) and the **layered pipeline** concept (Layer 3), but replace the macro engine (Layer 1) with a **simple Dictionary lookup and string template substitution**. The quasiquote notation is elegant but should be **flattened to `{slot}` replacement syntax** that any developer can understand. The bottom-up layering is good XP practice, but each layer should be **GDScript-idiomatic**, not Lisp-idiomatic.

---

## Cross-Cutting Analysis: What XP Values That the Other Plans Miss

### 1. Characterization Tests Before Any Change

Only the **Agile/Scrum plan** (Epic A) explicitly proposes characterizing the current codegen's behavior before changing it. This is **critical XP practice**: you cannot refactor safely without knowing what the system currently does. Every other plan jumps straight to building a replacement.

**XP recommendation**: *Every* plan should start with: run the current codegen on all test inputs, capture the outputs as golden files, and commit them. This is Sprint 0 / Step 0 for any refactoring effort.

### 2. Replace One Thing at a Time

The **XP plan** and **TDD plan** both propose incremental replacement — migrating one `generate_cmd_*` at a time. The **Functional Purity**, **Data-Oriented**, **Design Patterns**, and **Waterfall** plans all require big-bang rewrites.

**XP recommendation**: The template table should initially contain **only the instructions that currently exist in `op_map`**. Add new template entries one at a time, verifying against golden files after each addition.

### 3. Simple Data Structures Before Clever Ones

The **Unix** plan uses TSV (simplest possible). The **XP** plan uses a Dictionary of Dicts (simple, idiomatic GDScript). The **TDD** plan uses Objects. The **Lisp** plan uses S-expression arrays. The **Data-Oriented** plan uses parallel `PackedInt32Array`s.

**XP recommendation**: Start with the simplest data structure that works. In GDScript, that's a `Dictionary`. Optimize *only* when a profiler proves the Dictionary is a bottleneck.

### 4. Templates Are Data, Owned by the Whole Team

The **Unix** plan's TSV files, the **XP** plan's `template_table` constant, and the **Agile** plan's external YAML files all treat templates as data. The **Design Patterns** plan buries templates inside a `TemplateRegistry` object. The **Lisp** plan embeds them in the macro table.

**XP recommendation**: Templates should be in a **separate file** (TSV, JSON, or YAML) that can be edited without touching code. This enables **collective ownership** — the language designer, not just the codegen developer, can add instructions.

### 5. Working Software as Primary Measure

| Plan | Time to first working assembly output (estimated) |
|---|---|
| **XP** | **Day 1-2** (migrate `MOV` to template table) |
| **TDD** | Day 3-4 (after Increment 0 + Increment 1) |
| **Unix** | Week 1-2 (build 2-stage pipeline) |
| **Agile/Scrum** | Week 3-4 (end of Sprint 1) |
| **Literate** | Week 2-3 (after tangle tool setup) |
| **Functional Purity** | Week 3-4 (after pure infrastructure) |
| **Lisp Macro** | Week 3-4 (after macro engine) |
| **Design Patterns** | Week 4-6 (after 6 patterns implemented) |
| **Data-Oriented** | Month 2+ (after SoA migration) |
| **Waterfall** | Month 4+ (after Phase 3 implementation) |

---

## Final Verdict: Which Plans XP Can Work With

| Plan | XP Compatibility | Key Alliance Points | Key Conflicts |
|---|---|---|---|
| **XP Plan** (ours) | ✔️ **Native** | — | — |
| **TDD** | ✔️ **Strong ally** | Incremental, test-first, safe refactoring | Test infrastructure upfront |
| **Unix** | ✔️ **Compatible** | Simple pipeline, templates as data | Too many stages initially |
| **Agile/Scrum** | ✔️ **Compatible** | Golden files, sprint structure, DoD | Ceremony overhead, YAGNI stories |
| **Literate** | ⚠️ **Conditional** | Good architecture documentation | Tangle/weave toolchain |
| **Functional Purity** | ❌ **Tension** | Correct diagnosis of state problems | Big-bang purity, over-engineered types |
| **Lisp Macro** | ❌ **Tension** | Templates as data, bottom-up layers | Over-engineered pattern matching |
| **Design Patterns** | ❌ **Strong tension** | Template Registry concept | 6-pattern injection, class explosion |
| **Data-Oriented** | ❌ **Strong tension** | 4-bit bitmask register allocator | SoA migration, premature optimization |
| **Waterfall** | ❌ **Antithetical** | Template Catalog as reference | BDUF, sign-off gates, no feedback |

---

*Written from the XP trenches. Favor simplicity. Deliver incrementally. Own collectively. Refactor courageously. Measure progress in working software.*
