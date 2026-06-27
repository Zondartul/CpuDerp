# Agile/Scrum Advocate's Opinion: A Critical Review of All 9 Codegen Plans

> *"Inspect and adapt. Delight customers. Deliver working software frequently."* — The Agile Manifesto

**Author**: Agile/Scrum Advocate  
**Date**: 2026-06-27  
**Purpose**: Evaluate every competing codegen plan through the lens of iterative delivery, stakeholder visibility, adaptability to change, sprint-ability, estimation accuracy, and risk management.

---

## Table of Contents

1. [How I Evaluate](#1-how-i-evaluate)
2. [1. Functional Purity Plan](#2-functional-purity-plan)
3. [2. Data-Oriented Design Plan](#3-data-oriented-design-plan)
4. [3. Unix Philosophy Plan](#4-unix-philosophy-plan)
5. [4. TDD (Test-Driven Development) Plan](#5-tdd-test-driven-development-plan)
6. [5. XP (Extreme Programming) Plan](#6-xp-extreme-programming-plan)
7. [6. Design Patterns (GoF OOP) Plan](#7-design-patterns-gof-oop-plan)
8. [7. Literate Programming Plan](#8-literate-programming-plan)
9. [8. Waterfall / BDUF Plan](#9-waterfall--bduf-plan)
10. [9. Lisp Macro Plan](#10-lisp-macro-plan)
11. [Final Verdict: Ranked by Agile Fitness](#11-final-verdict-ranked-by-agile-fitness)

---

## 1. How I Evaluate

Every plan is judged on six axes:

| Axis | What I Look For |
|------|-----------------|
| **Iterative Delivery** | Can value be delivered incrementally, or is it all-or-nothing? Can I ship after Sprint 1? |
| **Stakeholder Visibility** | Do stakeholders see working software at each sprint review, or just documents and promises? |
| **Adaptability to Change** | If requirements shift mid-project, how painful is the course correction? |
| **Sprint-Ability** | Can the work be decomposed into 2-week sprints with clear sprint goals and shippable increments? |
| **Estimation** | How well can I estimate story points? Are the units small and well-understood? |
| **Risk Management** | What's the biggest risk, and how is it mitigated? |

---

## 2. Functional Purity Plan

**File**: [`plans/functional_purity_codegen_plan.md`](plans/functional_purity_codegen_plan.md)

### Iterative Delivery: 3/10

The plan's 5 phases are sequential — Phase 1 (define pure types) → Phase 2 (template engine) → Phase 3 (driver) → Phase 4 (integration) → Phase 5 (testing). There is no working software until Phase 4. A stakeholder attending the Sprint 1 review would see a file of pure function signatures, not assembly output. This violates the Agile principle of "working software is the primary measure of progress."

The plan claims Phase 2 "Template Engine" as a unit, but the template engine depends on the pure types from Phase 1. There's no thin vertical slice.

### Stakeholder Visibility: 2/10

Stakeholders care about assembly output. This plan produces pure data structures for multiple sprints before anything executable appears. The "Testing Strategy" section (Phase 5) — which demonstrates actual output — is the last thing implemented. In an Agile project, we'd want the first sprint to produce a single, end-to-end working path (e.g., `MOV` immediate → register) so the stakeholder can see real assembly text.

### Adaptability to Change: 5/10

Pure functions are inherently easy to refactor — no side effects to chase. If the stakeholder says "we need a new slot binding syntax," it's a localized change. However, the rigid algebraic type hierarchy (`Template`, `AssemblyResult`, `RegAllocState` — all defined as by-hand Dictionary structs) creates coupling. Changing `AssemblyResult` from 6 fields to 7 ripples through every function that returns it. In a changing environment, this ceremony slows adaptation.

### Sprint-Ability: 4/10

The phases are coarse. Phase 2 ("Build Template Engine") is at least 8 story points — too large for a single sprint without decomposition. The plan offers no sub-sprint milestones. An Agile team would need to re-slice this into smaller stories: "Build template engine: `MOV` template only" then "add `OP` templates" etc.

Positive note: the pure functions are independently testable, which makes CI-based sprint verification possible.

### Estimation: 6/10

The plan lists 5 phases but gives no time estimates. The phase boundaries are clear enough that a team could estimate them, but the estimates would be poor because the plan doesn't say how many templates, how many pure functions, or how complex the state threading is. As a Scrum Master, I'd ask: "How many functions? How many templates? What's the function-point count?"

### Risk Management: 4/10

**Biggest risk**: Performance. Pure functions in GDScript mean `duplicate()` calls on every state transition. For every register alloc, the entire `RegAllocState` Dictionary is copied. The plan notes "immutable copy on each transition" but does not measure the performance cost. In the ZVM codegen hot path, this could be catastrophic. Risk is not addressed.

**Second risk**: The plan is a rewrite, not a refactor. Agile prefers evolutionary design. If Phase 4 integration fails (the pure functions don't produce the same output as the existing codegen in all edge cases), there's no fallback position.

### Agile/Scrum Verdict

The functional purity plan produces **testable, refactorable code**, but it's architecturally rigid and has no incremental delivery story. It would work as the *output* of an Agile process, not as an *Agile process itself*.

**Score: 4/10** — High-quality destination; terrible journey.

---

## 3. Data-Oriented Design Plan

**File**: [`plans/data_oriented_codegen_plan.md`](plans/data_oriented_codegen_plan.md)

### Iterative Delivery: 2/10

This plan is the **least incremental** of the entire set. It defines a rigid three-pass pipeline (Analyze → Expand → Fixup) where Pass 2 cannot run without Pass 1, and Pass 3 cannot run without Pass 2. The entire flat IR data model (Section 4) — all 10+ static arrays — must be built before a single line of assembly is emitted.

There is **no thin vertical slice**. You cannot deliver "just MOV for immediate-to-register" without having built the whole SoA infrastructure, the symbol table flattening, the template bytecode compiler, and the fixup pass. This is the antithesis of iterative delivery.

### Stakeholder Visibility: 1/10

A stakeholder attending sprint reviews for 3 months would see: Sprint 1 — flat array definitions. Sprint 2 — template bytecode compiler. Sprint 3 — emit engine. No assembly output until everything works. The "inspect" part of "inspect and adapt" cannot happen because there's nothing to inspect until the very end.

### Adaptability to Change: 1/10

The SoA layout is **brittle**. Adding a new symbol attribute (e.g., `sym_is_volatile`) requires adding a new `PackedXxxArray`, finding all places that index into it, and updating the serialization/deserialization. Compare with adding a field to a Dictionary in the current codegen — trivial. The static global arrays make parallel work impossible: two developers cannot work on different parts of the codegen simultaneously because they'd conflict on the same module-level statics.

If a stakeholder says "we need a new type of IR operand," the entire SoA schema may need restructuring. The plan does not address this.

### Sprint-Ability: 1/10

The three-pass batch pipeline cannot be decomposed into meaningful sprint increments that deliver value. The passes are sequential dependencies by design. Sprint planning would be: "Sprint 1: Build the whole flat IR infrastructure." "Sprint 2: Build the whole template engine." "Sprint 3: Build the whole fixup pass." No decomposition is offered.

### Estimation: 3/10

The plan is data-heavy and algorithmic. Estimating the SoA flattening code is hard because the complexity depends on the IR structure, which varies. The template bytecode compiler (Section 5.4) is a non-trivial parsing and code generation task — a classic "unknown unknown" for estimation.

### Risk Management: 2/10

**Biggest risk**: The plan optimizes for performance that may not matter. The codegen runs once per compilation. Users won't notice whether it takes 5ms or 50ms. Yet the entire design sacrifices testability, maintainability, and incremental delivery for cache-friendly access patterns. This is a **misdirected optimization risk** — solving a problem that doesn't exist.

**Second risk**: Global static state makes testing near-impossible (the TDD critic will elaborate). Without testing, regressions are undetectable. The risk of shipping broken assembly is high.

### Agile/Scrum Verdict

This plan is the **most anti-Agile** in the set. It optimizes for machine performance over human productivity, requires everything to be built before anything works, and offers no incremental value delivery. It would take 3+ months before a stakeholder sees a single line of assembly.

**Score: 1/10** — A perfect example of what Agile was created to avoid.

---

## 4. Unix Philosophy Plan

**File**: [`plans/unix_philosophy_codegen_plan.md`](plans/unix_philosophy_codegen_plan.md)

### Iterative Delivery: 8/10

This plan scores well because the pipeline architecture naturally supports incremental delivery. Each stage (`ir2flat`, `sym_alloc`, `templ_expand`, `reg_resolve`, `line_asm`) is a independent text filter. You can build and ship them one at a time:

1. **Sprint 1**: Build `ir2flat` + a stub for the remaining stages that just passes text through. Stakeholder sees flat IR text output — not assembly, but *something working*.
2. **Sprint 2**: Build `sym_alloc`. Stakeholder sees storage assignments.
3. **Sprint 3**: Build `templ_expand` for `MOV` only. Stakeholder sees semi-resolved MOV assembly.
4. Continue adding templates stage by stage.

This is textbook "thin vertical slice" delivery. Each sprint produces visible output, even if it's an intermediate format.

### Stakeholder Visibility: 7/10

Because every stage reads and writes text, a stakeholder can inspect intermediate output at each sprint review. The plan explicitly mentions this on line 37: "You can pipe them together, redirect to files, or insert debugging stages (`tee`) anywhere in the pipeline." This transparency is excellent for stakeholder trust.

However, intermediate text formats (tab-separated IR lines) are not as exciting as final assembly output. The stakeholder would need technical context to appreciate "scope scp_0 global none" lines. But at least they can see *something*.

### Adaptability to Change: 7/10

Adding a new stage is trivial — insert it in the pipeline. Replacing a stage is easy — swap one filter for another. Changing the intermediate format is harder (it would affect all stages), but the plan's TSV format is well-documented.

The biggest adaptability weakness: the text-format intermediate representation is **fragile**. A missing tab or extra space breaks parsing. If stakeholders request a new data column, every stage that parses that line type needs updating.

### Sprint-Ability: 8/10

The 5-stage pipeline maps naturally to 5 sprint increments. Each stage is independently testable (feed text in, assert text out). Sprint goals are clear: "By end of Sprint, `sym_alloc` correctly assigns storage for all test programs."

The plan even shows test code (Section 8's "Why this exists" notes), which makes sprint acceptance criteria easier to define.

### Estimation: 6/10

Pipeline stages are well-defined but uneven in complexity. `ir2flat` is straightforward (YAML → flat text). `templ_expand` is complex (template parsing, pattern matching, multi-line expansion). The plan does not provide estimate ranges.

### Risk Management: 7/10

**Biggest risk**: Text-format parsing overhead. Every stage parses and re-serializes the entire IR. For large programs, this text-tax could slow the pipeline. The plan does not benchmark this.

**Mitigation**: Text formats are debuggable. If performance is an issue, you can optimize the bottleneck stage without affecting others — a classic Agile risk response (measure, then optimize).

**Second risk**: The pipeline is **asynchronous** in real Unix (pipes between processes) but in Godot it would be synchronous function calls — each stage processing a string in memory. This is fine, but the plan's Unix framing might mislead about parallelism opportunities.

### Agile/Scrum Verdict

The Unix plan is the **most naturally Agile** of the set. Pipeline stages are independent, incrementally deliverable, independently testable, and provide intermediate visibility. It's the closest to a thin-vertical-slice approach.

**Score: 8/10** — An architecture that practically begs for iterative delivery.

---

## 5. TDD (Test-Driven Development) Plan

**File**: [`plans/tdd_codegen_plan.md`](plans/tdd_codegen_plan.md)

### Iterative Delivery: 8/10

The 12 increments are a near-perfect sequence of thin vertical slices:
- Increment 1: Assembly text builder
- Increment 2: Register allocator
- Increment 3: Operand resolver
- Increment 4-6: Template engine
- Increment 7: MOV command (first real assembly output!)
- Increment 8-11: More commands
- Increment 12: Integration

By Increment 7, a stakeholder can see a MOV instruction being compiled to assembly. This is excellent iterative delivery. Each increment has a Red-Green-Refactor cycle that produces tested, working code.

The plan explicitly orders tests from simplest to most complex, with each building on the previous. This is textbook Scrum backlog ordering by dependency.

### Stakeholder Visibility: 7/10

Stakeholders see real assembly output by Increment 7 (the `MOV` command). However, the first 6 increments produce infrastructure: buffers, registers, resolvers, matchers. A non-technical stakeholder might struggle to see value in `test_write_pos_increment`. 

That said, the plan's test-first approach means the *tests themselves* are executable specifications — a stakeholder can see "given this IR input, the codegen produces this assembly output" as a concrete demonstration.

### Adaptability to Change: 9/10

This is the TDD plan's strongest Agile attribute. TDD's Red-Green-Refactor cycle is designed for change:
1. New requirement → write a failing test → make it pass → refactor.
2. Changing requirement → update the test → make it pass → refactor.
3. Removing requirement → delete the test → refactor.

The dependency injection architecture (Section 7) supports swapping implementations without breaking tests. Mock `SymTable`, mock `CodeBlockProvider` — all explicitly designed for change tolerance.

### Sprint-Ability: 9/10

The 12 increments map cleanly across sprints. A typical plan:
- Sprint 1: Increments 1-3 (infrastructure)
- Sprint 2: Increments 4-6 (template engine)
- Sprint 3: Increments 7-9 (MOV + OP + branching)
- Sprint 4: Increments 10-12 (calls, arrays, integration)

Each increment has clear acceptance criteria (the test itself), which is exactly what Scrum Definition of Done needs.

### Estimation: 8/10

TDD increments are small (2-10 minute Red-Green-Refactor cycles), which makes estimation unusually accurate. Each increment's scope is precisely defined by its test cases. The plan's edge case table (Section 9) gives a comprehensive view of scope, enabling accurate story pointing.

However, the plan doesn't explicitly provide story point estimates. As a Scrum Master, I'd need the team to point each increment, but the increments are small and well-understood — estimation should be quick.

### Risk Management: 7/10

**Biggest risk**: Testing culture dependency. TDD only works if the team is disciplined about writing tests first. If the team skips tests under pressure, the safety net disappears. The plan's 100% coverage goal is admirable but ambitious in practice.

**Mitigation**: CI gating on coverage + golden file comparison. The plan prescribes this implicitly.

**Second risk**: Over-testing. 13 edge cases × multiple increments = hundreds of tests. Maintenance burden. The plan does not address test maintenance cost.

### Agile/Scrum Verdict

The TDD plan is **excellently Agile** — small increments, tested deliverables, high adaptability. It's the only plan that explicitly structures its work around a "red-green-refactor" rhythm that maps perfectly to Scrum sprints. The dependency injection design makes it resilient to change.

**Score: 8/10** — TDD and Agile are natural allies. This plan proves it.

---

## 6. XP (Extreme Programming) Plan

**File**: [`plans/xp_codegen_plan.md`](plans/xp_codegen_plan.md)

### Iterative Delivery: 9/10

The XP plan is the **most incremental of all 9 plans**. It explicitly avoids a big-bang rewrite (line 27: "No big-bang rewrite"). Instead, it prescribes **6 sprints**, each replacing one piece of the existing codegen while keeping the system green:

- Sprint 1: Extract `PatternMatcher` — no functional change, pure refactor
- Sprint 2: Extract `SlotAllocator` — same output
- Sprint 3: Extract `SlotResolver` — same output
- Sprint 4: Convert IF/WHILE to templates
- Sprint 5: Convert CALL/RETURN to templates
- Sprint 6: Remove dead code

Every sprint produces identical assembly output (verified by tests). This is **continuous delivery without interruption** — the dream of every product owner. Stakeholders never see a broken pipeline.

### Stakeholder Visibility: 8/10

Each sprint delivers a "boring" result: same output as before. This is actually great for stakeholders — zero regressions, zero downtime. The stakeholder sees that the system continues to work while the internal architecture improves.

The downside: no visible progress on new features during the refactoring sprints. A stakeholder might ask "why are we spending 6 sprints producing the same output?" This requires educating the stakeholder on technical debt reduction.

### Adaptability to Change: 9/10

YAGNI is the core principle — only build what you need now. If requirements change, you simply don't build the parts you haven't started yet. The incremental migration strategy means you can stop at any sprint and still have a working codegen (some parts template-driven, some still in the old `generate_cmd_*` functions).

The plan's small file sizes (each pass is its own file) support collective code ownership — any developer can modify any pass. This reduces bus-factor risk.

### Sprint-Ability: 9/10

The 6 sprints are clearly defined, appropriately sized (each is 2-5 story points), and have unambiguous acceptance criteria: "same assembly output." Sprint goals are concrete and verifiable.

The plan explicitly notes "team size: 2 developers" and estimates velocity (15-20 points/sprint), which shows Scrum maturity. It also identifies risks per sprint and suggests fallback options (line 207: "If blocked, swap to C-4").

### Estimation: 8/10

The plan provides story point estimates for every story. The backlog items are small (2-8 points each), well-understood, and have clear "done" criteria. The 2-person team, 15-20 velocity estimate is realistic.

The only estimation concern: Sprint 5 (Migrate Call/Return) could be complex due to stack frame handling. The plan identifies this risk but doesn't provide buffer.

### Risk Management: 8/10

**Biggest risk**: The **parallel pipeline** — running old and new codegen side by side — doubles memory and CPU during migration. For the ZVM's small test programs this is fine, but the plan doesn't discuss the resource cost.

**Mitigation**: The plan's "same output" test strategy ensures zero regressions. The risk of shipping broken assembly is the lowest of any plan.

**Second risk**: Developer discipline. XP requires pair programming, TDD, collective ownership. If the team doesn't follow these practices, the incremental migration loses its safety net.

### Agile/Scrum Verdict

The XP plan is the **gold standard for Agile codegen replacement**. It delivers working software every sprint, manages risk through continuous testing, and allows stopping at any point with a working system. Every Agile principle is demonstrated.

**Score: 9/10** — If every plan were this pragmatically incremental, my job as Scrum Master would be easy.

---

## 7. Design Patterns (GoF OOP) Plan

**File**: [`plans/design_patterns_codegen_plan.md`](plans/design_patterns_codegen_plan.md)

### Iterative Delivery: 2/10

The GoF plan proposes **30 classes** across **8 GoF patterns** before any assembly is emitted. The architecture must be assembled before a single command is codegen'd. There is no thin vertical slice — just a massive upfront class design.

The plan is 1,100 lines of specification but contains **no incremental delivery sequence**. It says "Phase 1: Core Interfaces" then "Phase 2: Pattern Implementations" then "Phase 3: Integration" — classic waterfall dressed in OOP clothing.

### Stakeholder Visibility: 1/10

A stakeholder attending sprint reviews would see: Sprint 1 — `IIrCommand` interface definition. Sprint 2 — `MovCommand` class with Visitor accept method. Sprint 3 — `TemplateRegistry` with Strategy pattern registration. No assembly output until everything is wired together.

This is the lowest stakeholder visibility of any plan except Data-Oriented. The GoF patterns create **layers of indirection** that even a technical stakeholder would struggle to appreciate without detailed explanation.

### Adaptability to Change: 3/10

The GoF pattern catalog is **brittle under change**. Changing the Visitor pattern's `visit()` method signature requires updating all 13+ concrete command visitors. Adding a new pattern means creating new interfaces, new implementations, and updating the composite. The class explosion works against agility — every change touches multiple files.

The plan says "Favor composition over inheritance" (line 35) but then creates a deep hierarchy of 30 classes. Composition is used within patterns, but the pattern *application itself* creates rigid boundaries.

### Sprint-Ability: 2/10

30 classes across 8 patterns cannot be decomposed into 2-week sprints that deliver value. Sprint 1 would be "Implement the Command Pattern" — but the Command pattern has no value without the Visitor, Template, and Composite patterns to consume it. The dependencies form a directed acyclic graph that requires most patterns to exist before any can be exercised.

### Estimation: 2/10

30 classes with no implementation order, no dependencies mapped, no test strategy. Estimating this is a guessing game. The plan's "Implementation Order" section (Section 10) is vague: "Implement core interfaces first, then pattern implementations." This is not estimable.

### Risk Management: 2/10

**Biggest risk**: **Over-engineering**. The plan introduces 8 GoF patterns and 30 classes for a codegen that currently works in 833 lines of procedural code. The risk of "pattern happiness" (applying patterns because they're available, not because they're needed) is extreme. The Visitor pattern alone adds 20+ lines of boilerplate per IR command.

**Second risk**: Performance. 30 classes means 30× `RefCounted` allocation overhead. The multiple indirection layers (Visitor dispatch → Strategy lookup → Composite traversal → Decorator wrapping) create unpredictable performance. The plan doesn't address this.

### Agile/Scrum Verdict

The GoF plan is **architectural over-indulgence**. It's designed to showcase patterns, not to deliver working software incrementally. It would take 3+ months before a stakeholder sees value, and the resulting 30-class system would be hard to change.

**Score: 2/10** — A textbook example of Big Design Up Front dressed in GoF terminology.

---

## 8. Literate Programming Plan

**File**: [`plans/literate_codegen_plan.md`](plans/literate_codegen_plan.md)

### Iterative Delivery: 3/10

The literate plan is structured as one large document (1,130 lines) covering the entire design. While the document's sections could theoretically be implemented incrementally, the plan does not prescribe an implementation sequence. It's a specification, not a sprint plan.

The "tangling" concept (extracting code from the document) implies an all-at-once generation: you write the whole document, then tangle it into source files. This is the opposite of iterative — you can't tangle a half-written document and get compilable source.

### Stakeholder Visibility: 2/10

Stakeholders would see a beautiful, well-written document at each sprint review — prose, diagrams, code snippets. But they would not see working software until the implementation phase began. The plan conflates "documentation" with "deliverable." Agile values working software over comprehensive documentation.

A literate document is a wonderful *output* of an Agile project (for future maintainers), but a poor *input* to sprint reviews (the stakeholder wants to see assembly output, not a beautifully formatted explanation of how assembly output will work).

### Adaptability to Change: 3/10

The literate document is written as a cohesive narrative. Changing one section requires re-weaving the surrounding prose. If a stakeholder requests a pipelined architecture instead of a monolithic template engine, the literate author must rewrite significant portions of the narrative to maintain coherence.

The code and prose are interleaved — a change to the code requires a corresponding change to the explanation. This couples documentation and implementation more tightly than Agile would prefer.

### Sprint-Ability: 2/10

The plan has no sprint structure, no backlog, no estimation. It's organized by technical concern (architecture, data types, template engine, etc.) rather than by deliverable increment. An Agile team would need to completely re-slice the document into sprints, losing the literate narrative coherence.

### Estimation: 1/10

Without any decomposition into tasks or stories, estimation is impossible. The plan is a single 1,130-line document. How do you estimate "write a literate program"? The team has no prior data points.

### Risk Management: 3/10

**Biggest risk**: **Documentation debt**. The write-weave-tangle cycle is time-consuming. Under sprint pressure, teams will naturally favor writing code over writing explanations. The literate document becomes outdated quickly. The plan has no mechanism for keeping prose and code in sync under iterative development.

**Second risk**: Tooling dependency. Literate programming requires tangling/weaving tools. Godot has no such tools. The team would need to build or adopt one, adding project risk.

### Agile/Scrum Verdict

The literate plan produces the **best documentation** of any plan, but it treats the *design document* as the primary artifact, not *working software*. It cannot be delivered incrementally, has no sprint structure, and couples documentation so tightly to code that change becomes costly.

**Score: 2/10** — Beautiful documentation is lovely; but it's not Agile delivery.

---

## 9. Waterfall / BDUF Plan

**File**: [`plans/waterfall_codegen_plan.md`](plans/waterfall_codegen_plan.md)

### Iterative Delivery: 0/10

This is the **anti-pattern of iterative delivery**. The plan specifies 5 strictly sequential phases:
1. Requirements Specification (signed off)
2. Architecture & Design (signed off)
3. Implementation
4. Verification
5. Maintenance

Nothing is delivered until Phase 4 (Verification). Phase 1 alone is estimated at 40 person-hours. A sprint review after Phase 1 would show a requirements document — no working software. After Phase 2 — an architecture document. After Phase 3 — untested code. Only in Phase 4 would a stakeholder see assembly output.

This is the exact problem the Agile Manifesto was created to solve.

### Stakeholder Visibility: 0/10

Zero visibility into working software until the verification phase. Stakeholders see documents at phase gates. If Phase 1 requirements are wrong (and they always are), the error isn't discovered until Phase 4 — months later. The plan has no mechanism for early stakeholder feedback on actual behavior.

### Adaptability to Change: 0/10

The plan's sign-off gates are explicitly designed to *prevent* change. "Requirements are frozen before design begins" is stated in the core principle (line 7). If a stakeholder requests a change after Phase 2 sign-off, the plan requires re-opening Phase 1, updating the requirements traceability matrix (FR-01 through FR-43), re-signing off, and cascading through Phase 2.

The cost of change is exponential — exactly the waterfall model's fatal flaw.

### Sprint-Ability: 1/10

There are no sprints. The plan has phases, each with its own sign-off. The phases are not timeboxed (40 person-hours for Phase 1 is an estimate, not a timebox). There is no concept of "sprint goal" or "sprint backlog."

The plan could be *forced* into a sprint model by treating each phase as a sprint, but the phases are inherently sequential — you cannot stop after "Sprint 1" (requirements) and ship value.

### Estimation: 2/10

The plan provides some estimates (40 person-hours for Phase 1, 80 for Phase 2), but these are phase-level estimates without story-level decomposition. The Requirements Traceability Matrix lists 43 requirements (FR-01 through FR-43), but none are sized or prioritized beyond "Critical/Major/Minor."

The plan assumes all requirements are known upfront, which is the #1 cause of estimation failure in software projects.

### Risk Management: 1/10

**Biggest risk**: **All of them**. The waterfall model concentrates risk at the end of the project. Requirements may be wrong (discovered in Phase 4). Architecture may not work (discovered in Phase 4). Implementation may reveal design flaws (discovered in Phase 4). There is no early risk detection.

**Risk Register** (Section C): The plan contains a risk register but treats risks as static items to be documented, not as dynamic factors to be mitigated through iterative feedback.

**Second risk**: The plan is 1,705 lines — larger than the code it's replacing (833 lines). The overhead of specification exceeds the cost of the system being replaced. This is a sign of analysis paralysis.

### Agile/Scrum Verdict

The waterfall plan is **everything Agile was created to replace**. Sequential phases, frozen requirements, sign-off gates, late visibility, high change cost, concentrated risk. It's a museum piece of pre-Agile software engineering.

**Score: 0/10** — The antithesis of Agile delivery. If a team followed this plan, they'd deliver the wrong thing, too late, with no way to adapt.

---

## 10. Lisp Macro Plan

**File**: [`plans/lisp_macro_codegen_plan.md`](plans/lisp_macro_codegen_plan.md)

### Iterative Delivery: 3/10

The plan's bottom-up layer structure (Layer 0: S-expr primitives → Layer 1: macro engine → Layer 2: template definitions → Layer 3: macro passes → Layer 4: driver) is a classic **bottom-up design**. The problem for Agile: Layer 0 has no value without Layer 1, which has no value without Layer 2, etc. You cannot ship after Layer 0.

However, the plan's macro-based approach does allow **template-level increments** — once Layers 0-2 exist, you can add new templates iteratively (MOV → OP → IF → CALL, etc.). But getting to that point requires multiple sprints of infrastructure.

### Stakeholder Visibility: 3/10

Stakeholders would see S-expression data structures for multiple sprints before real assembly output appears. The plan does not provide a "minimal viable product" milestone.

Positive: the plan's "bottom-up" philosophy is transparent about the dependency chain — a stakeholder could be shown Layer 0 working ("here's how we represent IR commands as S-expressions") even though it's not assembly yet.

### Adaptability to Change: 7/10

Macros are **data** in the Lisp view — they live in a table, not in code. Adding a new instruction is "macro definition = data entry" which is highly adaptable. Changing the macro expansion rules is localized to the macro engine (Layer 1).

However, changing the S-expression representation itself (Layer 0) would cascade through all layers. The macro passes (Layer 3) are rigid in their ordering — you cannot easily reorder register-allocation before label-resolution.

### Sprint-Ability: 4/10

The 5 layers are coarse-grained. Each layer is multi-sprint work. An Agile team would need to re-slice: "Layer 0a: S-expr for MOV only" → "Layer 0b: S-expr for all commands" → "Layer 1a: macro expander for simple templates" → etc.

The plan does not offer this decomposition. It presents layers as monolithic units.

### Estimation: 3/10

The macro engine (Layer 1) is a non-trivial piece of infrastructure — pattern matching, rewriting, environment manipulation. Without prior experience building macro expanders, estimation would be highly uncertain. The plan provides no sizing.

### Risk Management: 4/10

**Biggest risk**: **GDScript unsuitability**. GDScript lacks macros, homoiconicity, and first-class symbolic expressions. The plan's central insight — "code is data, macros transform it" — cannot be directly expressed in GDScript. The plan acknowledges this (Section 2.4 "DSL Embedding") and proposes embedding a small DSL using dictionaries and arrays. But this embedded DSL is itself an unestimated piece of work.

**Mitigation**: None proposed. The plan doesn't address the GDScript-Lisp impedance mismatch risk.

**Second risk**: Performance. Macro expansion at runtime (interpreting S-expressions through a pattern matcher) is computationally expensive. The plan does not benchmark or estimate this.

### Agile/Scrum Verdict

The Lisp macro plan has interesting ideas (data-driven macros, bottom-up layering) but is poorly suited to Agile delivery. The bottom-up dependency chain means multiple sprints before value is visible, and the GDScript-Lisp mismatch introduces significant risk.

**Score: 3/10** — Elegant in concept; impractical in GDScript, and non-incremental in delivery.

---

## 11. Final Verdict: Ranked by Agile Fitness

| Rank | Plan | Score | Key Agile Strength | Key Agile Weakness |
|------|------|-------|-------------------|-------------------|
| 🥇 | **1. XP** | **9/10** | 6 incremental sprints, each keeping the system green | Requires team discipline for pair programming/CI |
| 🥈 | **2. TDD** | **8/10** | 12 test-driven increments with dependency injection | Test maintenance overhead |
| 🥉 | **3. Unix Philosophy** | **8/10** | Pipeline stages are natural sprint increments | Text-format fragility |
| 4 | Functional Purity | 4/10 | Pure functions are testable | No incremental delivery story |
| 5 | Lisp Macro | 3/10 | Macro-driven extensibility | GDScript-Lisp impedance mismatch |
| 6 | Literate Programming | 2/10 | Beautiful documentation | Documentation ≠ working software |
| 7 | Design Patterns (GoF) | 2/10 | Clean interfaces | 30-class over-engineering |
| 8 | Data-Oriented | 1/10 | Performance optimization | Three-pass batch, no iterativity |
| 9 | Waterfall / BDUF | **0/10** | Thorough specification | Antithesis of every Agile principle |

### Recommended Approach

As the Agile/Scrum Advocate, I recommend a **hybrid of XP and TDD**:
- Use the **XP plan's incremental migration strategy** — replace one command at a time, always keeping the system green.
- Use the **TDD plan's test-first discipline** and dependency injection — every new template has a failing test first.
- Use the **Unix plan's pipeline decomposition** as the target architecture — small, independent stages connected by clean interfaces.
- **Avoid** the Data-Oriented, GoF, and Waterfall approaches entirely — they are incompatible with iterative, stakeholder-visible delivery.

The result is a 6-sprint project (12 weeks for a 2-person team) that produces shippable software after every sprint, never breaks the existing pipeline, and builds a maintainable, data-driven codegen.

---

*"Working software over comprehensive documentation. Responding to change over following a plan. That is, while there is value in the items on the right, we value the items on the left more."*
