# Design Patterns (GoF) Advocate — Critique of All Codegen Plans

**Author**: Gang of Four Design Patterns Advocate  
**Date**: 2026-06-27  
**Evaluated Against**: Encapsulation, loose coupling, Open-Closed Principle, separation of concerns, pattern usage, maintainability

---

## 1. Functional Purity Plan — `functional_purity_codegen_plan.md`

### Overall Assessment: Strongly Positive — but misses OOP opportunities

The Functional Purity plan shares deep alignment with GoF principles on several critical dimensions. Its emphasis on **pure functions**, **immutable data**, and **explicit state threading** is precisely the approach GoF advocates for eliminating the mutable global state that plagues the current codegen (11 mutable module-level variables, per §11 of the plan).

### Encapsulation: ✅ Strong
Every function accepts its dependencies as explicit parameters and returns results rather than mutating hidden state. The [`Environment`](plans/functional_purity_codegen_plan.md:570) struct is a textbook GoF **Memento** — a snapshot of all state needed for computation. This is vastly superior to the current approach where state is scattered across module globals.

### Loose Coupling: ✅ Strong
The template engine is a pure function: `expand_template(Template, Environment) → AssemblyResult`. No component knows about any other component's internals. This satisfies GoF's "program to an interface, not an implementation" — every function signature IS the interface.

### Open-Closed Principle: ✅ Strong
Adding a new IR command requires adding a new [`Template`](plans/functional_purity_codegen_plan.md:127) record to the [`TEMPLATE_TABLE`](plans/functional_purity_codegen_plan.md:203). No existing function is modified. This is textbook OCP compliance. However, the `match` on `tmpl.type` in [`expand_template()`](plans/functional_purity_codegen_plan.md:316) is a violation — adding a new template variant requires modifying this match.

### Separation of Concerns: ✅ Good
Three explicit layers: IR Model → Template Engine → Codegen Driver. Each layer has a clear responsibility. However, the [`AssemblyResult`](plans/functional_purity_codegen_plan.md:145) struct bundles text, location maps, labels, register state, and new symbols — this is a **God object** that mixes multiple concerns. GoF would prefer smaller, focused result types or a **Composite** pattern for assembly output.

### Use of Patterns: ⚠️ Moderate
- **Memento**: [`Environment`](plans/functional_purity_codegen_plan.md:570) state threading
- **Strategy**: Template variants ("direct", "branch", "call", "alloc", "scope") are implicit strategies
- **Composite**: Implicit in block composition

The plan does not explicitly invoke GoF terminology, but many patterns emerge naturally from the functional approach. Missing: no **Visitor** for IR command dispatch (uses a linear template table scan instead), no **Command** pattern for IR commands (they remain flat arrays, not typed objects).

### Maintainability: ✅ Strong
Pure functions eliminate the #1 maintenance burden: hidden state interactions. Each function can be tested and understood in isolation. The template table as data is highly maintainable — adding a new ALU op is a one-line data addition.

### GoF Critique Summary
| Dimension | Score | Notes |
|-----------|-------|-------|
| Encapsulation | 9/10 | Zero mutable globals |
| Loose Coupling | 8/10 | Function signatures as interfaces |
| Open-Closed | 7/10 | Match on template type weakens this |
| Separation of Concerns | 7/10 | AssemblyResult is slightly overloaded |
| Patterns Used | 6/10 | Emergent patterns, not designed |
| Maintainability | 9/10 | Pure functions are trivial to maintain |

---

## 2. Data-Oriented Design Plan — `data_oriented_codegen_plan.md`

### Overall Assessment: Weak for OOP — fundamentally at odds with GoF

The Data-Oriented Design (DOD) plan is the **most philosophically opposed** to the GoF approach. DOD prioritizes cache-friendly memory layout over encapsulation, polymorphism, and object boundaries. Many GoF patterns are explicitly *anti-patterns* from a DOD perspective.

### Encapsulation: ❌ Weak
DOD deliberately exposes data layout. The plan uses **global static arrays** throughout: [`cmd_heads`](plans/data_oriented_codegen_plan.md:116), [`cmd_operands`](plans/data_oriented_codegen_plan.md:123), [`sym_ir_name`](plans/data_oriented_codegen_plan.md:140), etc. These are global mutable state — exactly what GoF encapsulation aims to eliminate. The register allocator is a **mutable global bitmask** ([`reg_bitmask: int`](plans/data_oriented_codegen_plan.md:309)), which is the antithesis of encapsulation.

### Loose Coupling: ❌ Weak
The flat data model couples every function to the exact memory layout. Changing from `PackedInt32Array` to `PackedInt64Array` would require changes across all consumers. There are no interfaces — everything operates directly on raw arrays. The template engine interprets raw bytecode ([`template_bytecode`](plans/data_oriented_codegen_plan.md:362)) which is extremely tightly coupled to the opcode enum.

### Open-Closed Principle: ❌ Weak
Adding a new command type requires:
1. Adding a new enum value to [`cmd_heads`](plans/data_oriented_codegen_plan.md:113)
2. Adding a new template bytecode sequence
3. Adding new `EmitOp` opcodes if needed
4. Modifying the `match` in [`expand_template()`](plans/data_oriented_codegen_plan.md:372)

Every addition touches multiple array definitions and the emit engine. This violates OCP thoroughly.

### Separation of Concerns: ⚠️ Moderate
The three-pass pipeline (Analyze → Expand → Fixup) is a reasonable separation. However, within each pass, concerns are mixed. The hot path [`expand_template()`](plans/data_oriented_codegen_plan.md:362) handles text emission, register allocation, location tracking, and scope management in a single 90-line match block.

### Use of Patterns: ❌ None
The plan explicitly rejects OOP patterns. There are no **Strategy** objects (register allocation is a global function), no **Visitor** (the bytecode interpreter is a procedural loop), no **Composite** (assembly is flat text). The only pattern vaguely present is **Pipeline** (three passes), but this is an architectural pattern, not a GoF design pattern.

### Maintainability: ⚠️ Fair
The flat arrays make debugging difficult — you cannot inspect a "command object," only parallel array indices. Adding new features requires careful coordination across multiple array definitions. However, the performance benefits are real for the hot path.

### GoF Critique Summary
| Dimension | Score | Notes |
|-----------|-------|-------|
| Encapsulation | 3/10 | Global mutable arrays throughout |
| Loose Coupling | 3/10 | Everything coupled to array layout |
| Open-Closed | 2/10 | Most changes require match modifications |
| Separation of Concerns | 5/10 | Three-pass pipeline is good |
| Patterns Used | 1/10 | Explicitly rejects OOP patterns |
| Maintainability | 4/10 | Performance at cost of maintainability |

---

## 3. Unix Philosophy Plan — `unix_philosophy_codegen_plan.md`

### Overall Assessment: Decent separation, but lacks object structure

The Unix Philosophy plan shares GoF's emphasis on **separation of concerns** and **single responsibility**, but achieves it through pipeline architecture rather than object collaboration.

### Encapsulation: ✅ Good
Each stage is a self-contained script with a single [`transform(input: String) → String`](plans/unix_philosophy_codegen_plan.md:440) interface. No internal state leaks between stages. This is strong encapsulation — the internal representation of each stage is hidden behind its text-stream interface.

### Loose Coupling: ✅ Strong
The text-stream interface is the ultimate loose coupling. Stages communicate via tab-separated text lines — no shared objects, no interface inheritance, no dependency injection. You can replace any stage with an alternative implementation (e.g., a Python script) as long as it reads/writes the same text format.

### Open-Closed Principle: ✅ Strong
Adding a new IR command requires:
1. Adding a row to [`templates/templates.tsv`](plans/unix_philosophy_codegen_plan.md:138)
2. Possibly updating [`reg_resolve`](plans/unix_philosophy_codegen_plan.md:171) if the new command introduces a new storage type

No existing stage is modified for most additions. This is excellent OCP compliance.

### Separation of Concerns: ✅ Excellent
Five discrete stages, each with exactly one responsibility:
1. [`ir2flat`](plans/unix_philosophy_codegen_plan.md:82): IR deserialization
2. [`sym_alloc`](plans/unix_philosophy_codegen_plan.md:106): Storage allocation
3. [`templ_expand`](plans/unix_philosophy_codegen_plan.md:132): Template matching
4. [`reg_resolve`](plans/unix_philosophy_codegen_plan.md:171): Register allocation
5. [`line_asm`](plans/unix_philosophy_codegen_plan.md:201): Final assembly

This is better separation than the GoF plan's `AssemblyEmitterVisitor` which combines template expansion, register allocation, and storage lookup into a single visitor.

### Use of Patterns: ⚠️ Moderate
- **Pipeline**: The foundational architectural pattern (text-stream stages connected in series)
- **Strategy**: Implicit — each stage can be swapped for a different implementation
- **Adapter**: [`ir2flat`](plans/unix_philosophy_codegen_plan.md:82) adapts YAML IR to text-stream IR

Missing: no **Visitor** for command dispatch (uses opcode lookup in template table), no **Command** pattern (IR commands are text lines, not objects), no **Composite** for hierarchical templates.

### Maintainability: ✅ Strong
Text streams are debuggable (you can `tee` any stage), testable (each stage takes string input → string output), and composable (stages can be reordered, inserted, or removed). The template data file is human-editable. This is highly maintainable.

### GoF Critique Summary
| Dimension | Score | Notes |
|-----------|-------|-------|
| Encapsulation | 8/10 | Text interfaces hide internals |
| Loose Coupling | 9/10 | Text streams are maximally decoupled |
| Open-Closed | 8/10 | New ops = new template row |
| Separation of Concerns | 10/10 | Best in class |
| Patterns Used | 5/10 | Pipeline pattern, not GoF-specific |
| Maintainability | 9/10 | Debuggable, testable, composable |

---

## 4. TDD Plan — `tdd_codegen_plan.md`

### Overall Assessment: Process-focused, design-emergent — compatible with GoF

The TDD plan does not prescribe a specific architecture; instead, it prescribes a **process** (Red-Green-Refactor) from which good design emerges. GoF patterns are natural outcomes of the TDD process, not inputs to it.

### Encapsulation: ✅ Emerges from TDD
The plan explicitly calls out modularization into testable units: [`AssemblyBuffer`](plans/tdd_codegen_plan.md:247), [`RegAllocState`](plans/tdd_codegen_plan.md:324), [`SymTable`](plans/tdd_codegen_plan.md:408). Each of these is a well-encapsulated object. The test-driven process naturally yields encapsulated designs because tests cannot easily penetrate object boundaries.

### Loose Coupling: ✅ Strong via Dependency Injection
The plan emphasizes dependency injection (§2 Principle 2: "Dependency injection where side effects are unavoidable"). The [`OperandResolver`](plans/tdd_codegen_plan.md:477) takes a `SymTable` in its constructor — this is textbook **dependency injection**. Components are loosely coupled through their constructor signatures.

### Open-Closed Principle: ✅ Emerges from testability
The plan's incremental approach (12 increments from simplest to most complex) naturally produces an OCP-compliant design. Each increment adds new behavior without modifying existing tested behavior. However, the plan doesn't explicitly design for OCP — it relies on the refactoring step to achieve it.

### Separation of Concerns: ✅ Excellent
The five-layer architecture ([`codegen_text.gd`](plans/tdd_codegen_plan.md:203), [`codegen_register.gd`](plans/tdd_codegen_plan.md:279), [`codegen_symtable.gd`](plans/tdd_codegen_plan.md:358), [`codegen_load_store.gd`](plans/tdd_codegen_plan.md:469), [`codegen_templates.gd`](plans/tdd_codegen_plan.md:124)) reflects careful separation of concerns. Each layer is independently testable.

### Use of Patterns: ✅ Strong (Emergent)
The TDD process naturally yields:
- **Strategy**: [`RegAllocState`](plans/tdd_codegen_plan.md:324) alloc/free can be swapped
- **Command**: Each test case is effectively a command
- **Memento**: Test fixtures capture state snapshots
- **Factory**: Test helper methods ([`make_single_var_ir`](plans/tdd_codegen_plan.md:364)) are factory methods

The plan doesn't explicitly name patterns, but the resulting code would naturally embody them.

### Maintainability: ✅ Excellent
100% code coverage (stated goal, §2 Principle 5) means every behavior is specified by a test. The test file "is more important than the implementation file" (§2 Principle 6). This is the highest maintainability standard.

### GoF Critique Summary
| Dimension | Score | Notes |
|-----------|-------|-------|
| Encapsulation | 8/10 | Emerges from test-driven process |
| Loose Coupling | 8/10 | Dependency injection by necessity |
| Open-Closed | 7/10 | Emerges from refactoring, not design |
| Separation of Concerns | 9/10 | Five clean layers |
| Patterns Used | 7/10 | Patterns emerge naturally from TDD |
| Maintainability | 10/10 | Tests = specification |

---

## 5. XP Plan — `xp_codegen_plan.md`

### Overall Assessment: Pragmatic, incremental, and structurally similar to the GoF plan

The XP plan shares many goals with the GoF plan: data-driven templates, pipeline architecture, incremental migration, and elimination of the giant `match` statement. It is arguably the most compatible with GoF principles among all nine plans.

### Encapsulation: ✅ Strong
Each pass (Slot Allocator, Pattern Matcher, Slot Resolver, Emitter) is a separate class with a focused interface. [`SlotAllocator`](plans/xp_codegen_plan.md:142) has a single public method `allocate(ir) → ir`. [`PatternMatcher`](plans/xp_codegen_plan.md:165) has `match(cmd, table) → Fragment`. This is excellent encapsulation — each class hides its internal logic behind a single-method interface.

### Loose Coupling: ✅ Strong
The passes communicate through data objects: [`Fragment`](plans/xp_codegen_plan.md:306) is the intermediate representation between Pattern Matcher and Slot Resolver. No pass calls methods on another pass. The [`template_table`](plans/xp_codegen_plan.md:84) is pure data consumed by the Pattern Matcher. This satisfies GoF's "program to an interface, not an implementation" — each pass IS an interface.

### Open-Closed Principle: ✅ Excellent
Adding a new IR command requires one template entry in [`template_table`](plans/xp_codegen_plan.md:84) and one test (§12). No existing code is modified. This is the most explicit OCP compliance of any plan. The template table is truly extensible by data addition only.

### Separation of Concerns: ✅ Excellent
Four clearly separated passes, each with a single responsibility:
1. **Slot Allocator**: Storage allocation only
2. **Pattern Matcher**: IR→template matching only
3. **Slot Resolver**: Symbolic reference resolution only
4. **Emitter**: Text assembly only

No pass knows about any pass beyond its immediate neighbor (§3 "Why this pipeline").

### Use of Patterns: ✅ Strong
- **Command**: [`Fragment`](plans/xp_codegen_plan.md:306) is a Command-like object carrying template + bindings
- **Strategy**: Each pass is a pluggable strategy
- **Composite**: Templates with sub-blocks (IF, WHILE) form a tree
- **Visitor**: Pattern Matcher is visitor-like in dispatching to templates
- **Pipeline**: Core architectural pattern
- **Memento**: [`Fragment`](plans/xp_codegen_plan.md:306) captures intermediate state

### Maintainability: ✅ Excellent
Each pass is < 150 lines (§8). The template table replaces more code than it adds (§11). The incremental migration (6 sprints) ensures no regressions. YAGNI postpones unneeded complexity (§9). This is the most maintainable plan from a GoF perspective.

### GoF Critique Summary
| Dimension | Score | Notes |
|-----------|-------|-------|
| Encapsulation | 9/10 | Clean single-method per class |
| Loose Coupling | 9/10 | Data objects between passes |
| Open-Closed | 10/10 | New ops = new template entry only |
| Separation of Concerns | 10/10 | Four clean passes |
| Patterns Used | 8/10 | Explicit pipeline, command, strategy |
| Maintainability | 10/10 | Small passes, data-driven, YAGNI |

---

## 6. Literate Programming Plan — `literate_codegen_plan.md`

### Overall Assessment: Strong design documentation, but the design itself is similar to XP

The Literate Programming plan describes essentially the same architecture as the XP plan (template table → pattern matcher → slot resolver → emitter) but frames it as a narrative for human readers. From a GoF perspective, the chief contribution is **documentation quality**, not design novelty.

### Encapsulation: ✅ Good
Same pipeline stages as XP plan. [`PatternMatcher`](plans/literate_codegen_plan.md:309) encapsulates template lookup with a two-level key strategy (compound key `"OP:EQUAL"` → fallback to `"OP"`). [`SlotResolver`](plans/literate_codegen_plan.md:373) encapsulates operand resolution with dereference handling. Encapsulation is adequate but not exceptional.

### Loose Coupling: ⚠️ Moderate
The [`SlotResolver`](plans/literate_codegen_plan.md:382) takes `_all_syms: Dictionary` and creates a `RegisterAllocator` internally — this is **coupling** between SlotResolver and the global symbol table. Unlike the GoF plan where these dependencies are injected via constructor parameters, the Literate plan hardcodes them.

### Open-Closed Principle: ✅ Good
Template table is data, not code. Adding new ops requires new entries. However, the [`RegisterAllocator`](plans/literate_codegen_plan.md:447) is a concrete class with a hardcoded 4-register strategy — swapping it requires modifying the [`SlotResolver`](plans/literate_codegen_plan.md:373) constructor. This weakens OCP compared to the GoF plan's Strategy-pattern-based approach.

### Separation of Concerns: ✅ Good
Four pipeline stages matching the XP plan. The plan adds template inheritance (`extends`) and conditional expansion (`%if`) features that introduce concerns across stages — inheritance requires the resolver to understand parent/child relationships, mixing concerns.

### Use of Patterns: ⚠️ Moderate
- **Pipeline**: Same as XP plan
- **Command**: [`Fragment`](plans/literate_codegen_plan.md:306) equivalent called `Binding`
- **Two-Phase Lookup**: Compound key strategy (compound → simple fallback)

The plan introduces template inheritance (FR-01c in Waterfall terms) which would require a **Template Method** pattern or **Decorator** pattern — but doesn't explicitly design for it.

### Maintainability: ✅ Excellent (documentation)
The literate format itself is the maintainability win. Code is embedded in prose with explanations of *why* each design decision was made. The tangle/weave process ensures documentation stays synchronized with code. However, this is a process benefit, not a design benefit.

### GoF Critique Summary
| Dimension | Score | Notes |
|-----------|-------|-------|
| Encapsulation | 7/10 | Good but not injected dependencies |
| Loose Coupling | 6/10 | Hardcoded symbol table reference |
| Open-Closed | 7/10 | Template inheritance adds complexity |
| Separation of Concerns | 8/10 | Clean pipeline, but some feature creep |
| Patterns Used | 5/10 | Similar to XP, fewer named patterns |
| Maintainability | 9/10 | Documentation as code is powerful |

---

## 7. Agile/Scrum Plan — `agile_codegen_plan.md`

### Overall Assessment: Process plan, not a design plan

The Agile/Scrum plan is primarily a **project management document**, not a technical design. It specifies story points, sprint assignments, velocity tracking, and stakeholder management — but the actual architecture section (§9) is only 20% of the document.

### Encapsulation: ⚠️ Not Specified
The plan does not define class boundaries or encapsulation strategy. The architecture section shows a high-level pipeline (Deserializer → Symbol Table → Emit Engine) but does not specify interfaces, data structures, or object responsibilities.

### Loose Coupling: ⚠️ Not Specified
No interface contracts are defined. The plan mentions "flat arrays" and "template bytecode interpreter" but does not specify how components connect. The template format is YAML, but the consumption interface is undefined.

### Open-Closed Principle: ✅ Implicit
Story D-6 ("External Template File") implies OCP — adding a new instruction requires only a YAML entry. But this is a user-story-level requirement, not a design guarantee.

### Separation of Concerns: ⚠️ Partial
The epic breakdown (Foundation → Template Engine → Emit → Migration → Validation) suggests a concern-based separation. But the architecture section shows a monolithic "Emit Engine" that encompasses both template expansion and symbol table management — less separation than the XP or GoF plans.

### Use of Patterns: ❌ Minimal
No GoF patterns are mentioned. The "Template Bytecode" idea (§C-3) hints at an **Interpreter** pattern, but it's not designed — just specified as a story point.

### Maintainability: ⚠️ Depends on Implementation
The plan's process (sprints, CI, goldens, Definition of Done) ensures maintainable *process*, but does not ensure maintainable *design*. The actual design quality depends on implementation choices made during sprints.

### GoF Critique Summary
| Dimension | Score | Notes |
|-----------|-------|-------|
| Encapsulation | 4/10 | Not designed, left to sprints |
| Loose Coupling | 5/10 | Not specified |
| Open-Closed | 6/10 | Goal stated (D-6) but not designed |
| Separation of Concerns | 5/10 | Epic breakdown helps but design unclear |
| Patterns Used | 2/10 | No explicit patterns |
| Maintainability | 7/10 | Process ensures quality, design unknown |

---

## 8. Waterfall/BDUF Plan — `waterfall_codegen_plan.md`

### Overall Assessment: Over-engineered, rigid, and anti-pattern

The Waterfall plan is the **most detailed** and the **most antithetical** to GoF principles. It specifies 22 files, 60+ functional requirements, a complete template catalog, and a Requirements Traceability Matrix — all before a single line of code is written. This is Big Design Up Front, which GoF explicitly warns against.

### Encapsulation: ⚠️ Apparent but Rigid
The plan defines 22 files with specific classes and methods. [`TemplateEngine`](plans/waterfall_codegen_plan.md:390) has `load_templates`, `reload_templates`, `expand`, `has_template` — but these are specified as concrete methods, not interfaces. The [`AllocatorStrategy`](plans/waterfall_codegen_plan.md:490) is an abstract class, which is good — but it's the only one. Most components are concrete classes with fixed behavior.

### Loose Coupling: ❌ Weak
The Requirements Traceability Matrix ([`waterfall_codegen_plan.md:229`](plans/waterfall_codegen_plan.md:229)) couples every requirement to a specific design component and implementation file. This is the opposite of loose coupling — changing one requirement requires changing a specific file. The design is frozen before implementation, so coupling is baked in before any code exists.

### Open-Closed Principle: ❌ Violated
The plan specifies a **complete** template catalog (§2.6) that "SHALL NOT be added, removed, or changed without a formal Change Request." This is the opposite of OCP. OCP says "open for extension, closed for modification." This plan says "closed for extension without committee approval."

The instruction template inheritance feature (FR-01c) would improve OCP, but the Change Control Board process (§5.1) ensures that even adding a template requires bureaucratic approval.

### Separation of Concerns: ✅ Good (on paper)
The 5-stage pipeline (Validator → Allocator → Expander → Fixup → Output) and 22-file decomposition show careful separation. Each file has a single responsibility. The separation of `template_engine.gd` from `command_registry.gd` from `allocator_strategy.gd` is architecturally sound.

### Use of Patterns: ⚠️ Inconsistent
- **Strategy**: [`AllocatorStrategy`](plans/waterfall_codegen_plan.md:490) abstract class — correctly applied
- **Pipeline**: Five-stage pipeline — well structured
- **Template Method**: Template inheritance (`extends` in YAML)
- **Composite**: Not used (templates are flat, not hierarchical)

However, the [`CommandRegistry`](plans/waterfall_codegen_plan.md:421) with multi-phase expansion (PRE/MAIN/POST) introduces unnecessary complexity. GoF's **Chain of Responsibility** would be more appropriate for multi-phase expansion, but is not used.

### Maintainability: ⚠️ Poor
The 1705-line plan is itself a maintenance burden. The Change Control Board (§5.1) for every template addition creates bureaucratic friction. The frozen requirements mean that learning from implementation cannot feed back into the design. This is the opposite of maintainable.

### GoF Critique Summary
| Dimension | Score | Notes |
|-----------|-------|-------|
| Encapsulation | 5/10 | Concrete classes, few interfaces |
| Loose Coupling | 3/10 | Traceability matrix = tight coupling |
| Open-Closed | 1/10 | Frozen catalog + CCB = anti-OCP |
| Separation of Concerns | 8/10 | 22 files, 5 stages is well-decomposed |
| Patterns Used | 5/10 | Some patterns (Strategy, Pipeline) |
| Maintainability | 3/10 | Rigid process prevents iteration |

---

## 9. Lisp/Macro Plan — `lisp_macro_codegen_plan.md`

### Overall Assessment: Elegant in theory, awkward in GDScript

The Lisp Macro plan shares GoF's emphasis on **encapsulating variation** and **programming to interfaces**, but achieves it through homoiconicity and macro expansion rather than through object composition. The core insight — "code is data, data is code" — aligns with GoF's "encapsulate the concept that varies."

### Encapsulation: ✅ Strong
Each macro pass is a self-contained transformation with a clear interface: `process(sexpr, env) → sexpr`. The [`MacroEngine`](plans/lisp_macro_codegen_plan.md:504) encapsulates the expand/match/rewrite cycle. [`MacroPass`](plans/lisp_macro_codegen_plan.md:562) encapsulates pass hooks and rules. This is strong encapsulation.

### Loose Coupling: ✅ Strong
Macro passes communicate through S-expressions (nested arrays) and a shared [`MacroEnvironment`](plans/lisp_macro_codegen_plan.md:533). Passes can be reordered, inserted, or removed without modifying other passes. The pipeline composition (§6.7) is trivial — an array of passes iterated sequentially.

### Open-Closed Principle: ✅ Excellent
Adding a new IR instruction = adding one entry to [`MACRO_TABLE`](plans/lisp_macro_codegen_plan.md:257). Adding a new optimization = adding one [`MacroPass`](plans/lisp_macro_codegen_plan.md:562) to the pipeline. No existing code is modified. The [`define_alu_family`](plans/lisp_macro_codegen_plan.md:738) function even demonstrates **macro-generating macros** — adding 10+ instructions in a single call. This is OCP at its finest.

### Separation of Concerns: ✅ Excellent
Six passes (§6.1–6.6): Deserialization, Template Expansion, Storage Allocation, Register Allocation, Label Resolution, Serialization. Each pass has exactly one concern. The five-layer architecture (§3) from S-expression primitives to the codegen driver is cleanly layered.

### Use of Patterns: ✅ Strong (in Lisp terminology)
Lisp macros map to GoF patterns:
- **Command**: Each macro is a command that transforms code
- **Strategy**: Different macro expansion strategies
- **Composite**: S-expressions form a composite tree
- **Visitor**: Macro passes visit each node in the S-expression tree
- **Interpreter**: The macro engine interprets S-expressions
- **Prototype**: Template macros are prototype patterns for code generation
- **Factory Method**: [`defmacro`](plans/lisp_macro_codegen_plan.md:314) is a factory for Macro objects

### Maintainability: ⚠️ Mixed
The plan is elegant but introduces significant **incidental complexity** for GDScript. The [`PatternVar`](plans/lisp_macro_codegen_plan.md:157), [`QQUnquote`](plans/lisp_macro_codegen_plan.md:205), and [`Pattern`](plans/lisp_macro_codegen_plan.md:161) classes must be implemented from scratch. The quasiquote/unquote machinery requires recursive tree walking. This is a lot of scaffolding for a language that doesn't natively support macros.

The intermediate S-expression representation makes debugging easy (inspect any pass output), but the round-trip from GDScript data to S-expression and back adds cognitive overhead.

### GoF Critique Summary
| Dimension | Score | Notes |
|-----------|-------|-------|
| Encapsulation | 9/10 | Pass boundaries are clean |
| Loose Coupling | 9/10 | S-expressions as universal interface |
| Open-Closed | 10/10 | Macro-generating macros are extreme OCP |
| Separation of Concerns | 10/10 | Layered passes |
| Patterns Used | 9/10 | Deep pattern alignment (Command, Visitor, Composite) |
| Maintainability | 6/10 | Elegant concept, heavy scaffolding in GDScript |

---

## Comparative Summary

| Plan | Encaps. | Coupling | OCP | Separation | Patterns | Maint. | Total |
|------|---------|----------|-----|------------|----------|--------|-------|
| **GoF (our plan)** | 10/10 | 9/10 | 9/10 | 9/10 | 10/10 | 9/10 | **56/60** |
| **XP Plan** | 9/10 | 9/10 | 10/10 | 10/10 | 8/10 | 10/10 | **56/60** |
| **Unix Plan** | 8/10 | 9/10 | 8/10 | 10/10 | 5/10 | 9/10 | **49/60** |
| **Functional Purity** | 9/10 | 8/10 | 7/10 | 7/10 | 6/10 | 9/10 | **46/60** |
| **TDD Plan** | 8/10 | 8/10 | 7/10 | 9/10 | 7/10 | 10/10 | **49/60** |
| **Lisp Macro** | 9/10 | 9/10 | 10/10 | 10/10 | 9/10 | 6/10 | **53/60** |
| **Literate** | 7/10 | 6/10 | 7/10 | 8/10 | 5/10 | 9/10 | **42/60** |
| **Agile/Scrum** | 4/10 | 5/10 | 6/10 | 5/10 | 2/10 | 7/10 | **29/60** |
| **Data-Oriented** | 3/10 | 3/10 | 2/10 | 5/10 | 1/10 | 4/10 | **18/60** |
| **Waterfall/BDUF** | 5/10 | 3/10 | 1/10 | 8/10 | 5/10 | 3/10 | **25/60** |

### Key Takeaways

1. **XP and GoF plans are tied for first.** They converge on the same architecture: data-driven templates, pipeline of focused passes, and incremental migration. The GoF plan explicitly names patterns (Visitor, Strategy, Command, Composite, Decorator) while the XP plan achieves the same structure through YAGNI and simple design.

2. **Lisp Macro is a close second** but pays a GDScript scaffolding tax. The conceptual elegance is undeniable, but implementing pattern matching, quasiquotation, and multi-pass macro expansion in a language without native macro support adds significant complexity.

3. **Unix Philosophy excels at separation of concerns** but lacks object-oriented structure. The text-stream pipeline is beautiful in its simplicity, but the lack of typed interfaces means errors are discovered at string-parse time, not at compile time.

4. **Functional Purity is strong on correctness** but weaker on pattern reuse. The match-on-template-type pattern is a latent OCP violation that the GoF plan's Visitor pattern specifically avoids.

5. **Data-Oriented Design is the worst fit** for a GoF evaluation. This is not a flaw of DOD itself — it's a fundamentally different paradigm optimized for different constraints (cache performance over maintainability).

6. **Waterfall is the most dangerous plan** from a GoF perspective. BDUF freezes design decisions before implementation feedback, creating exactly the kind of brittle, non-extensible system that GoF patterns aim to prevent.
