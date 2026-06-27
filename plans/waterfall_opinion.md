# Waterfall / BDUF Advocate — Critique of the Other 9 Plans

**Author**: Waterfall / Big Design Up Front Advocate  
**Date**: 2026-06-27  
**Reference**: [`waterfall_codegen_plan.md`](./waterfall_codegen_plan.md) — the only plan with complete specification rigor

---

## Preamble

I have reviewed all nine competing plans. Each contains valuable insights. None match the engineering rigor of a proper waterfall approach. The recurring failures are predictable: incomplete specifications, absent traceability, no formal change control, and verification strategies that are afterthoughts rather than integral to the design. Below, I evaluate each plan against the six criteria that separate professional engineering from prototyping.

---

## 1. Functional Purity Plan ([`functional_purity_codegen_plan.md`](./functional_purity_codegen_plan.md))

### Completeness of Specification: 3/10

The plan specifies a pure functional architecture and provides example code for template expansion, register allocation, and fixup. However, it never enumerates functional requirements. There is no requirements table, no non-functional requirements with measurable targets, and no interface contract. The entire specification is a collection of GDScript pseudocode snippets — implementation hints, not a specification. A complete specification would define *what* before *how*.

### Traceability: 2/10

There is zero traceability. No requirement IDs exist. No mapping from source-code locations to design elements to test cases. The plan asserts that adding a new IR command means adding a Template record, but it does not trace which current `generate_cmd_*` functions correspond to which templates. The file-by-file comparison table (Section 11) is the closest thing to traceability, but it maps to the *old* code, not to new requirements.

### Phase Discipline: 1/10

The plan has five phases (define types → build engine → build driver → integrate → test). This is a reasonable ordering, but there are no **sign-off gates** between phases. No criteria for when a phase is complete. No change-control mechanism if a phase discovers issues with earlier decisions. This is a to-do list, not a phase plan.

### Change Control: 1/10

No change control is described. The plan assumes that pure functions can be composed indefinitely without architectural drift. In practice, a new IR command that doesn't fit the "direct" or "branch" or "call" template variants would require adding a new variant to `expand_template()`'s match block — a specification change with no review process.

### Verification Rigor: 4/10

The plan correctly identifies that pure functions are testable without mocks (Section 12). The example test for `expand_mov_template` is well-structured. However, there is no test-case catalog, no regression strategy, no performance benchmarks, and no acceptance criteria. Testability is a property, not a plan.

### Overall Engineering Rigor: 2/10

The functional purity plan is a mathematically elegant design. But elegance is not engineering. Without requirements, traceability, phase gates, and change control, this is a research prototype dressed in type signatures. The insistence on referential transparency is admirable, but it does not substitute for a complete specification.

---

## 2. Data-Oriented Design Plan ([`data_oriented_codegen_plan.md`](./data_oriented_codegen_plan.md))

### Completeness of Specification: 5/10

The plan provides detailed flat-array schemas (Section 4) and a template bytecode format (Section 5). This is the most architecturally specific plan after the waterfall plan. However, it lacks a requirements specification. The functional requirements of the current codegen are not enumerated, and there is no mapping from current behavior to the new flat representation. The template bytecode opcode enum (`EmitOp`) is well-defined, but there is no specification of what correct output looks like.

### Traceability: 3/10

The plan traces performance problems in the current code (Section 1 table) to DOD violations. This is good. But there is no forward traceability from DOD design decisions to verification tests. The flat symbol table design (Section 4.2) is not traced to any requirement — it's justified by "cache friendliness," not by a requirement that specifies a cache-miss rate.

### Phase Discipline: 2/10

The three-pass pipeline (Analysis → Template Expansion → Fixup) is clearly defined, but the *project* phases are not. There is no implementation ordering, no milestones, no sign-offs. The plan describes what to build, not how to build it in a controlled manner.

### Change Control: 1/10

No change-control mechanism. The plan assumes the SoA layout is the optimal final form. If a new IR command requires a new parallel array or a different packing strategy, there is no process for evaluating the impact on the existing layout.

### Verification Rigor: 3/10

The plan mentions "cache-friendly" and "batch processing" as quality attributes but provides no measurable targets for either. There is no test strategy. The performance claims (e.g., "8 commands fit in a single 64-byte cache line") are theoretical. No performance benchmark is specified to validate them.

### Overall Engineering Rigor: 3/10

The DOD plan is strong on data-layout specifics but weak on everything that surrounds the code. It's an excellent low-level design document masquerading as a project plan. The focus on flat arrays and pre-compiled bytecode is technically sound, but without requirements, traceability, and verification, the implementation risks optimizing the wrong things.

---

## 3. Unix Philosophy Plan ([`unix_philosophy_codegen_plan.md`](./unix_philosophy_codegen_plan.md))

### Completeness of Specification: 4/10

The plan specifies a six-stage pipeline (Section 3) with textual intermediate formats described as tab-separated lines. The TSV format is well-specified. However, the functional requirements are absent. The plan describes *how* data flows between stages (text streams) but does not specify *what* each stage must compute. The template format (Section 4) is specified as a TSV, but there is no schema for the template syntax (sigils `$`, `@`, `^`) beyond informal examples.

### Traceability: 2/10

The plan traces current-code violations to Unix principles (Section 1 table), but this is a diagnosis, not a traceability matrix. No stage in the new pipeline is traced back to a specific requirement or to a specific function in the current codegen. The pipeline stages are motivated by "separation of concerns," not by a requirements decomposition.

### Phase Discipline: 2/10

The pipeline stages are well-ordered, and the end-to-end invocation (Section 3.3) shows how they compose. But there are no implementation phases. The plan does not specify whether to build stages top-down or bottom-up, or how to validate each stage before proceeding to the next. The pipe metaphor (stdin → stdout) suggests independent testing but doesn't enforce a sequential development discipline.

### Change Control: 1/10

No change control. The Unix philosophy of "do one thing well" implies that adding a new concern means adding a new stage. But the plan does not describe how to add or remove stages without destabilizing the pipeline. If a new stage needs to run before `sym_alloc` but after `ir2flat`, there is no process for evaluating that insertion.

### Verification Rigor: 3/10

The text-stream architecture enables testing each stage in isolation (you can pipe data through any single stage). This is a genuine strength. However, the plan does not specify test cases, expected outputs, or a regression strategy. The claim that "you can insert `tee` between stages for debugging" is a debugging tactic, not a verification plan.

### Overall Engineering Rigor: 3/10

The Unix plan has a clean architectural vision but lacks the specification and process discipline to execute it reliably. The text-stream pipeline is a good decomposition, but the plan reads like a Unix tutorial, not an engineering project plan. It tells you the right way to structure code but not how to ensure it works correctly.

---

## 4. TDD Plan ([`tdd_codegen_plan.md`](./tdd_codegen_plan.md))

### Completeness of Specification: 6/10

This is the first plan (after the waterfall plan) that specifies something approaching a complete system. The layer diagram (Section 3) defines six layers with specific file names. The test plan (Section 4) enumerates 12 increments with detailed test cases and expected code. The template data structure is well-specified. What's missing: a requirements specification. The TDD plan specifies *what the code should do* through test cases, which is functionally equivalent, but the tests are implementation-oriented rather than requirements-oriented.

### Traceability: 4/10

The increment structure provides forward traceability from increment number to tests to implementation. This is better than most plans. However, the increments trace to *test cases*, not to functional requirements. There is no requirements ID that connects, say, a business need for "template-driven opcode expansion" to a specific test in Increment 4.

### Phase Discipline: 5/10

The 12 increments are strictly ordered by dependency (assembly text builder → register allocator → operand resolver → template matcher → ...). This is genuine phase discipline. However, there are no sign-off gates. The plan defines what each increment implements but not the criteria for declaring it complete beyond "tests pass." There is no design review between increments.

### Change Control: 3/10

The Red-Green-Refactor cycle provides a built-in change-control mechanism: a failing test is a change request, and the implementation must satisfy it. However, the plan does not address what happens when a change cuts across increments (e.g., a new IR command that requires changes to both the template matcher and the operand resolver). Cross-cutting changes require a higher-level change-control process that this plan lacks.

### Verification Rigor: 8/10

This is the strongest aspect of the TDD plan. 100% code coverage is stated as a goal (Section 2, principle 5). The 12-increment structure ensures that every component is tested in isolation before integration. The test infrastructure (Section 4, Increment 0) is specified before any production code. The use of golden-file regression testing is specified. This is the only plan besides the waterfall plan that has a pre-defined regression strategy.

### Overall Engineering Rigor: 5/10

The TDD plan excels at verification but is weak at specification and traceability. It is the second-most rigorous plan after the waterfall plan, for one reason: it prioritizes correctness over cleverness. The incremental structure and pre-defined test catalog demonstrate engineering discipline. However, the lack of a requirements specification means the tests themselves become the de facto specification — and tests are a poor substitute for a document that stakeholders can review and sign off on.

---

## 5. XP Plan ([`xp_codegen_plan.md`](./xp_codegen_plan.md))

### Completeness of Specification: 4/10

The XP plan specifies a pipeline of four passes (Section 3) and a declarative template table (Section 4). The template schema is reasonably complete. However, the implementation specification is minimal — the plan describes what the components do but not their interfaces or contracts. The "simplest thing that works" philosophy is invoked repeatedly as a substitute for specification completeness. The plan simply asserts that YAGNI (You Aren't Gonna Need It) justifies not specifying anything beyond the current sprint.

### Traceability: 2/10

The plan has no requirements traceability. The six sprints (Sections 6.1–6.6) are ordered by refactoring sequence, not by requirements decomposition. There is no mapping from current codegen functions to new pipeline components. The plan assumes that if the output is byte-identical, the refactoring is correct — but it never traces which output bytes correspond to which IR commands.

### Phase Discipline: 3/10

The six-sprint structure imposes some phase discipline, but each sprint's output is "the system still works." There are no intermediate milestones that deliver a subset of functionality. The plan explicitly says "We do not flip a switch" — but that's a deployment strategy, not a phase discipline. The discipline comes from the tests (golden file comparison), not from specification deliverables.

### Change Control: 2/10

The XP philosophy embraces change ("Courage") but has no formal mechanism for evaluating it. The plan says "refactor mercilessly," but refactoring without a frozen specification is like remodeling a house without blueprints — you can change anything, but you don't know what you'll end up with. The collective ownership principle means anyone can change anything, which is the antithesis of change control.

### Verification Rigor: 5/10

The plan correctly identifies the need for byte-identical output (Sprint 1, test). The golden-file comparison strategy is sound. Each sprint has a "Test" step. However, there is no unit-test specification, no coverage target, and no performance benchmark. The verification strategy is "compare output to old codegen" — which is necessary but not sufficient. A regression from the old codegen would not be caught.

### Overall Engineering Rigor: 3/10

The XP plan is the most honest about its informality, but honesty does not equal rigor. The incremental migration strategy is pragmatically sound — replacing one IR command at a time is lower risk than a big-bang rewrite. However, the lack of requirements, traceability, and change control makes this a refactoring sketch, not an engineering plan. It would work for a small, well-understood codebase with a small team, but it does not scale.

---

## 6. Design Patterns (GoF OOP) Plan ([`design_patterns_codegen_plan.md`](./design_patterns_codegen_plan.md))

### Completeness of Specification: 5/10

The GoF plan is the most detailed in terms of class hierarchy and interface design. The Command pattern (Section 3.1), Visitor pattern (Section 3.2), Strategy pattern (Section 3.3), Template Method pattern (Section 3.4), and Composite pattern (Section 3.5) are all specified with concrete GDScript class skeletons. The interface for `RegisterAllocator`, `StorageAllocator`, and `TemplateProvider` are well-defined. What's missing: a requirements specification, a data schema, and a complete template catalog. The plan specifies the *container* (design patterns) but not the *contents* (the actual template data and pipeline details).

### Traceability: 3/10

The "Varying Aspects" table (Section 2.3) traces each design pattern to a concern in the current codegen (e.g., "Opcode→Assembly mapping" → Strategy pattern). This is good. But the traceability stops there. There is no mapping from design patterns to test cases, nor from pattern interfaces to functional requirements. The design patterns are justified by GoF principles, not by project requirements.

### Phase Discipline: 2/10

The plan has no implementation phases. It specifies what to build (interfaces, classes, patterns) but not the order of construction. Building a Visitor pattern requires all concrete `IrCommand` subclasses to exist first, but the plan does not specify whether to implement MovCommand before OpCommand or vice versa. There are no milestones, no sign-offs.

### Change Control: 4/10

The GoF plan has the best implicit change control of any non-waterfall plan. The Open-Closed Principle (classes open for extension, closed for modification) is a formal change-control mechanism: when a new IR command is needed, you create a new `IrCommand` subclass and add a `visit_*` method to the Visitor interface. You do not modify existing classes. This is a well-defined extension path. However, the plan does not specify a review process for interface changes (e.g., adding a new visit method).

### Verification Rigor: 3/10

The plan does not specify any test strategy. The design patterns ensure certain structural properties (encapsulation, loose coupling), but structural properties do not guarantee functional correctness. The plan assumes that if the architecture is clean, the code will be correct — a dangerous assumption. There are no test cases, no coverage targets, no regression strategy.

### Overall Engineering Rigor: 4/10

The GoF plan is the most architecturally sophisticated of the non-waterfall plans. The disciplined use of design patterns provides modularity and extensibility. However, the plan is an architectural sketch, not a complete specification. It tells you how to organize the classes but not what the classes should compute. The absence of a test plan is a critical gap. A building with a beautiful frame but no floors is uninhabitable.

---

## 7. Literate Programming Plan ([`literate_codegen_plan.md`](./literate_codegen_plan.md))

### Completeness of Specification: 5/10

The literate plan is the most readable and well-explained of all the plans. The prose is clear, the code examples are well-chosen, and the rationale for each design decision is explained. The template table (Section 3) is the most complete template catalog of any plan except the waterfall plan — it enumerates all ALU ops, control flow, stack operations, and special cases like INDEX. The documentation-first approach forces a certain completeness because the author must explain every design decision. However, this completeness is uneven: the template table is thorough, but the pipeline design (Section 2) is high-level, and the tangling/weaving process (Section 1.1) is described as a future capability rather than a present specification.

### Traceability: 3/10

The literate plan provides excellent backward traceability to the existing code through source-file references (e.g., "compare with line 12 of `codegen_md.gd`"). The side-by-side comparisons (Section 3, comparing old `op_map` with new template table) are instructive. But there is no forward traceability from design elements to verification. The plan explains *why* the design is better but does not specify *how* to verify it.

### Phase Discipline: 2/10

The plan has no phases, no milestones, no sign-offs. It is a complete design document (in the waterfall sense of a design document), but it does not specify the sequence of implementation. The tangling process (extracting code from documentation) could theoretically enforce an ordering, but the plan does not define one.

### Change Control: 2/10

No change control is described. The literate programming philosophy implies that changes should be made in the documentation (the source of truth) and then re-tangled, but the plan does not specify a review or approval process for those changes. If a developer modifies the tangled code without updating the documentation, the entire literate programming value proposition collapses.

### Verification Rigor: 3/10

The plan does not specify a test strategy. It argues that the code is verifiable because it is well-explained, which confuses understanding with correctness. A well-written explanation of a buggy algorithm is still a buggy algorithm. The plan mentions that "each pass is testable in isolation" (Section 2.1) but provides no test cases or assertions.

### Overall Engineering Rigor: 3/10

The literate plan is an excellent document for human comprehension. It is the best-written of all the plans, and the template table is more complete than any non-waterfall plan. But it is a design document, not an engineering plan. It explains the design but does not specify how to execute it with discipline. The assumption that readability equals correctness is the plan's fundamental weakness.

---

## 8. Agile/Scrum Plan ([`agile_codegen_plan.md`](./agile_codegen_plan.md))

### Completeness of Specification: 6/10

The Agile plan is the most complete non-waterfall plan in terms of project-management specification. It has a product vision, stakeholder analysis, epic breakdown, story-level specification, acceptance criteria (Section 2), definition of done (Section 3), sprint plan with 6 sprints (Section 4), and a delivery roadmap (Section 5). The technical architecture (Section 9) is comparatively thin — the template schema, data structures, and pipeline design are summarized rather than specified. The plan specifies the *process* thoroughly but the *product* sketchily.

### Traceability: 5/10

The story IDs (A-1 through E-6) provide a traceability structure. Each story has acceptance criteria. The sprint-plan table (Section 4) maps stories to sprints and shows dependencies. This is the best traceability of any non-waterfall plan. However, the stories trace to *tasks*, not to *requirements*. A story like "B-1 Template Parser" is a design task, not a requirement. There is no requirements decomposition that justifies why the template parser is needed in terms of user or system needs.

### Phase Discipline: 6/10

The sprint structure imposes genuine phase discipline. Six 2-week sprints with defined sprint goals, deliverables, and ceremonies (Sprint Planning, Daily Stand-up, Sprint Review, Retrospective) is a complete project management framework. The sprint backlog, velocity planning, and risk management (Section 6) are well-specified. However, the sprint boundaries are permeable — stories can be deferred (the plan explicitly says "if B-1 + B-2 exceed 13 points, defer B-4"). In waterfall, this would require a formal Change Request.

### Change Control: 5/10

The Scrum framework provides a well-defined change-control mechanism through the product backlog. New requirements become new backlog items. Changing priorities is done through backlog grooming and sprint planning. The definition of done (Section 3) provides a quality gate. This is the only non-waterfall plan with any formal change-control process. However, the plan does not address what happens when a change cuts across multiple sprints or requires rework of previously "done" stories.

### Verification Rigor: 6/10

The Agile plan has the most comprehensive verification strategy after the waterfall plan. Epic E (Validation & Hardening) is dedicated entirely to verification. Stories E-1 (golden file regression), E-2 (stress testing), E-3 (error recovery), E-4 (edge cases), E-5 (register pressure), and E-6 (performance benchmarks) form a complete verification suite. The Definition of Done includes code review, golden file pass, unit test coverage, linting, and documentation — six verification gates.

### Overall Engineering Rigor: 6/10

The Agile plan is the most complete non-waterfall plan and the closest to waterfall rigor. It has traceability (through story IDs), phase discipline (through sprints), change control (through backlog management), and verification (through Definition of Done and Epic E). Its weakness is that the technical specification is thin compared to the waterfall plan — the architecture section is an afterthought, and the template schema is not defined. A team following this plan would need to do significant design work during the sprints, which is where the risk of architectural drift enters.

---

## 9. Lisp/Macro Plan ([`lisp_macro_codegen_plan.md`](./lisp_macro_codegen_plan.md))

### Completeness of Specification: 4/10

The Lisp plan specifies a macro expansion engine (Section 4) with pattern matching, quasiquote expansion, and a multi-pass pipeline (Section 6). The template table (Section 8.5) is reasonably complete for ALU operations and control flow. However, the specification is uneven: the macro engine is overspecified (with full GDScript implementation for `match`, `expand`, `expand_qq`) but the actual template data is incomplete (no stack operations, no array operations, no ENTER/LEAVE). The plan specifies the plumbing in detail but leaves the components to be filled in later.

### Traceability: 2/10

The plan has a comparison table (Section 7) that maps current-codegen concerns to macro-driven equivalents. This is helpful for understanding the mapping but lacks the rigor of a traceability matrix. There is no forward traceability from macro definitions to verification tests. The six implementation phases (Section 9) are task-oriented, not requirements-oriented.

### Phase Discipline: 3/10

The six implementation phases (Section 9) provide an ordering: Sexpr Foundation → ALU Templates → Control Flow → Register Allocation → Label Resolution → Integration. This is a reasonable build-up order. However, there are no sign-off gates, no completion criteria, and no design reviews between phases. The phases are sequential in dependency but not in governance.

### Change Control: 2/10

The macro system provides a built-in extension mechanism: adding a new instruction = adding a macro definition. This is good for routine extensions. However, for architectural changes — adding a new macro pass, changing the pattern matching algorithm, modifying the environment structure — there is no change-control process. The metaprogramming flexibility (macros that write macros, Section 10.2) is powerful but increases the risk of ungoverned complexity.

### Verification Rigor: 3/10

The plan correctly observes that inspecting intermediate sexpr outputs is easier than inspecting side-effectful state (Section 10.1). This is a genuine debugging advantage. However, there is no test strategy, no test-case catalog, and no regression plan. The phase descriptions say "Test: Generate identical assembly" but do not specify how. The plan confuses observability with verification — being able to see intermediate states is not the same as having a systematic process for validating them.

### Overall Engineering Rigor: 3/10

The Lisp plan is intellectually ambitious and technically interesting. The macro-expansion pipeline and homoiconic representation are elegant concepts. But elegance does not equal engineering. The plan overspecifies the macro infrastructure while underspecifying the actual template data. The absence of requirements, traceability, and verification planning means this is a research project, not an engineering project. The deepest irony: for a philosophy that celebrates "code as data," the plan has very little data and a lot of code.

---

## Summary Comparison

| Criterion | Waterfall | Func Pure | DOD | Unix | TDD | XP | GoF | Literate | Agile | Lisp |
|---|---|---|---|---|---|---|---|---|---|---|
| **Spec Completeness** | **10** | 3 | 5 | 4 | 6 | 4 | 5 | 5 | 6 | 4 |
| **Traceability** | **10** | 2 | 3 | 2 | 4 | 2 | 3 | 3 | 5 | 2 |
| **Phase Discipline** | **10** | 1 | 2 | 2 | 5 | 3 | 2 | 2 | 6 | 3 |
| **Change Control** | **10** | 1 | 1 | 1 | 3 | 2 | 4 | 2 | 5 | 2 |
| **Verification Rigor** | **10** | 4 | 3 | 3 | 8 | 5 | 3 | 3 | 6 | 3 |
| **Overall** | **10** | 2 | 3 | 3 | 5 | 3 | 4 | 3 | 6 | 3 |

### Key Takeaways

1. **No plan (except the waterfall plan) has a complete requirements specification.** Every other plan jumps from diagnosis to design without specifying what "done" means. The TDD plan comes closest, using tests as a surrogate specification, but tests are implementation-level, not requirements-level.

2. **The Agile plan is the closest runner-up.** It has traceability (story IDs), phase discipline (sprints), change control (backlog management), and verification (Definition of Done). Its weakness is technical depth — the architecture section is thin, and the template schema is underspecified. A hybrid approach combining Agile's project management discipline with waterfall's specification rigor would be ideal.

3. **The TDD plan has the best verification strategy** after the waterfall plan. The 12-increment structure with pre-written tests is disciplined. But verification without specification is like a court without a law — you can check correctness, but you don't know what "correct" means.

4. **The GoF plan has the best change-control mechanism** through the Open-Closed Principle and Visitor pattern. But architectural extensibility is not the same as project change control. You can extend the code without extending the requirements.

5. **The Lisp and Functional Purity plans are the most intellectually elegant** but the least complete as engineering plans. They specify interesting ideas but not complete systems. A mathematician would love them; a project manager would not.

6. **Every plan underestimates the cost of incomplete specification.** The waterfall plan [`waterfall_codegen_plan.md`](./waterfall_codegen_plan.md) at 1,705 lines is the longest precisely because it specifies every requirement, every interface, every template, and every test case before any code is written. The other plans are shorter because they defer specification to implementation — which is exactly where cost overruns originate.

### The Waterfall Verdict

*"Measure twice, cut once."* The other nine plans measure once (diagnose the current code) and cut nine times (implement with incomplete specifications). The waterfall plan measures ten times (requirements, architecture, decomposition, data dictionary, template catalog, pipeline design, error handling, file manifest, implementation order, coding standards) and cuts once.

The aggregate cost of ambiguity across the other nine plans will manifest as:
- **Rework**: Each plan's incomplete specification guarantees that implementation will discover missing details, requiring backtracking.
- **Integration failures**: Without interface specifications as precise as the waterfall plan's YAML template schema and command descriptor format, pipeline stages will not compose correctly on the first attempt.
- **Scope creep**: Without a requirements specification with sign-off, every new idea during implementation becomes a "quick change" with no impact analysis.
- **Untestable gaps**: Without a test-case catalog, the other plans will ship with untested edge cases that the waterfall plan has already enumerated.

The waterfall plan [`waterfall_codegen_plan.md`](./waterfall_codegen_plan.md) is the only plan that qualifies as an engineering specification. The others are design sketches, technical explorations, or project management outlines. They are valuable inputs to the design process but are not substitutes for a complete, traceable, phase-disciplined engineering plan.
