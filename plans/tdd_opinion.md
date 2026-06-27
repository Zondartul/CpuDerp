# TDD Advocate's Opinion: A Critical Review of All 9 Codegen Plans

**Author**: Test-Driven Development Advocate  
**Date**: 2026-06-27  
**Purpose**: Evaluate every competing codegen plan through the lens of testability, dependency injection, test-first design, incremental confidence, and overall fitness for a TDD workflow.

---

## Table of Contents

1. [How I Evaluate](#1-how-i-evaluate)
2. [1. Functional Purity Plan](#2-functional-purity-plan)
3. [2. Data-Oriented Design Plan](#3-data-oriented-design-plan)
4. [3. Unix Philosophy Plan](#4-unix-philosophy-plan)
5. [4. XP (Extreme Programming) Plan](#5-xp-extreme-programming-plan)
6. [5. Design Patterns (GoF OOP) Plan](#6-design-patterns-gof-oop-plan)
7. [6. Literate Programming Plan](#7-literate-programming-plan)
8. [7. Agile/Scrum Plan](#8-agilescrum-plan)
9. [8. Waterfall / BDUF Plan](#9-waterfall--bduf-plan)
10. [9. Lisp Macro Plan](#10-lisp-macro-plan)
11. [Final Verdict: Ranked by TDD Fitness](#11-final-verdict-ranked-by-tdd-fitness)

---

## 1. How I Evaluate

Every plan is judged on five axes:

| Axis | What I Look For |
|------|-----------------|
| **Testability** | Can individual units be tested in isolation without mocks, file I/O, or global state? |
| **Dependency Injection** | Are dependencies explicit and injectable, or are they hardcoded globals? |
| **Tests as First-Class Citizens** | Does the plan mention tests at all? Are tests designed *before* or *after* implementation? |
| **Incremental Testable Increments** | Can I verify correctness after each small step, or must I wait until the whole thing is built? |
| **Confidence Through Testing** | Does the design inspire trust? Can I prove it works through a test suite, or must I rely on manual testing? |

---

## 2. Functional Purity Plan

### File: [`./plans/functional_purity_codegen_plan.md`](./plans/functional_purity_codegen_plan.md)

### Verdict: **Strong Alignment — Almost TDD-Compatible**

### Testability: 9/10

This plan is the closest competitor to TDD in terms of raw testability. Every function is pure — same input always produces same output, zero side effects. State is threaded explicitly through return values rather than mutated in place.

```gdscript
# The plan's pure function signature is exactly what a test wants:
static func compile_program(sym_table: Dictionary, ir_program: Dictionary) -> Dictionary:
```

I can call `compile_program({...}, {...})` with crafted inputs and assert on the returned `AssemblyResult` without setting up any global state. This is **textbook testable design**.

### Dependency Injection: 7/10

The plan threads state through parameters, which *is* a form of dependency injection. However, the `SymTable`, `RegAllocState`, and `AssemblyResult` are all plain `Dictionary` types — there are no interfaces, no abstract base classes, no way to swap implementations. If I want to test with a mock symbol table, I have to construct a Dictionary with the exact key structure the resolver expects. There's no `ISymTable` interface I can implement.

The template table is a `const` — hardcoded in source. I cannot inject a different template table for testing edge cases (e.g., a template that produces an invalid assembly string, or a template that triggers every error path).

### Tests as First-Class Citizens: 4/10

The plan **never mentions tests**. Not once. The word "test" appears zero times in the entire document. This is the single biggest gap. The architecture is *accidentally* testable because pure functions are inherently testable, but the plan doesn't:

- Propose a test file structure
- Show a single test case
- Suggest a test runner
- Define a red-green-refactor cycle
- Address how to test error paths (the code shows `push_error` calls but no test for them)

It has testable *potential*, not a test *strategy*.

### Incremental Testable Increments: 8/10

Each pure function can be tested independently: test `_resolve_slot` with a known env, test `compile_block` with a known code block, test `_alloc_register` with known register state. The plan's decomposition into small functions naturally supports incremental testing.

However, the plan doesn't *prescribe* an order. It doesn't say "start with the register allocator, get it green, then add slot resolution, then template expansion." It presents the whole thing as a complete design.

### Confidence Through Testing: 6/10

If tests were added, confidence would be high — pure functions are easy to reason about and cover exhaustively. But as written, the plan provides **no confidence at all**. The `AssemblyResult` Dictionary has 6 fields; missing one field will cause silent `null` errors in downstream consumers. Without tests proving each field is populated correctly, this is just a well-structured but unverified design.

### TDD Critique Summary

| Strength | Weakness |
|----------|----------|
| Pure functions are maximally testable | Zero test strategy, no test examples |
| State threading avoids global mutation | No dependency injection interfaces |
| Small functions support isolation | Template table is a hardcoded `const` |
| Referential transparency simplifies assertions | No incremental order prescribed |

**Bottom line**: The Functional Purity plan builds a house that *could* be tested, but doesn't show you how to test it. If its author collaborated with a TDD advocate, the result would be excellent. As-is, it's architecture without verification — a cathedral with no scaffolding.

---

## 3. Data-Oriented Design Plan

### File: [`./plans/data_oriented_codegen_plan.md`](./plans/data_oriented_codegen_plan.md)

### Verdict: **TDD Hostile — Performance Before Testability**

### Testability: 2/10

This plan is a nightmare for unit testing. The entire design is built around **static global arrays**:

```gdscript
static var cmd_heads: PackedInt32Array
static var cmd_operand_offset: PackedInt32Array
static var reg_bitmask: int = 0
```

Static state means tests **cannot run in isolation**. Running `test_mov_expansion` will mutate `reg_bitmask`, and if the next test expects a clean register state, it fails. You'd need to reset *every* static array between tests — a fragile, error-prone ritual that the plan doesn't address.

The SoA (Structure of Arrays) layout makes assertions painful. Instead of:

```gdscript
assert_eq(result.text, "mov EAX, 5;\n")
```

You'd have to write:

```gdscript
assert_eq(asm_buffer.slice(0, asm_write_pos), ...)
```

But `asm_buffer` is a `PackedByteArray`, so you're asserting on raw bytes, not strings. Every test becomes a hex dump comparison.

### Dependency Injection: 1/10

Zero. Everything is `static`. You cannot inject a different allocator, a different template table, or a different output buffer. The `alloc_register_hot()` function directly reads and writes `reg_bitmask` — a module-level static variable. There is no object to create, no interface to implement, no constructor to parameterize.

If I wanted to test with a mock register allocator that always returns `REG_NONE` (to force spilling), I **cannot**. The hot-path allocator is hardcoded.

### Tests as First-Class Citizens: 1/10

The plan does not mention testing. At all. The word "test" appears only in the context of "test programs" in the existing codebase, not in the design.

### Incremental Testable Increments: 1/10

The plan is explicitly **three-pass batch processing**: Pass 1 (analyze all), Pass 2 (expand all), Pass 3 (fixup all). You cannot run Pass 2 without completing Pass 1. You cannot test the emit engine without first building the entire flat IR representation. There is no "test Pass 2 with a hand-crafted flat IR" because the flat IR is built by Pass 1.

This is the antithesis of incremental testing. It's an all-or-nothing batch pipeline.

### Confidence Through Testing: 2/10

Even if you *could* test this, the bit-level operations (4-bit bitmask for register allocation, `PackedInt32Array` opcodes, `PackedByteArray` for assembly) make debugging failures extremely difficult. A register allocation bug would manifest as a wrong bit in an integer. An emit bug would manifest as wrong bytes in a buffer. Neither gives you a clear error message like "expected 'mov EAX, 5;\n' but got 'mov EBX, 5;\n'."

### TDD Critique Summary

| Strength | Weakness |
|----------|----------|
| Cache-friendly performance | Global static state destroys test isolation |
| Compact data representation | Zero dependency injection |
| Pre-compiled bytecode eliminates string scanning | Batch pipeline prevents incremental testing |
| Three-pass pipeline is conceptually clean | Bit-level operations make debugging opaque |

**Bottom line**: This plan optimizes for the wrong thing. Performance of a codegen that runs once per compilation is irrelevant compared to correctness and maintainability. The static global state makes it **untestable by design** — the same sin as the current [`codegen_md.gd`](../scenes/codegen_md.gd) that the plan claims to replace.

---

## 4. Unix Philosophy Plan

### File: [`./plans/unix_philosophy_codegen_plan.md`](./plans/unix_philosophy_codegen_plan.md)

### Verdict: **Good Intentions, Text-Format Tax**

### Testability: 7/10

Each stage is a pure text filter: `transform(input: String) -> String`. This is inherently testable — feed it a string, assert on the output string.

```gdscript
func test_sym_alloc_globals():
    var input = "scope\tscp_0\tglobal\tnone\n"
    input += "val\tscp_0\tx\tvariable\tint\tNULL\t\tx\n"
    var expected = "scope\tscp_0\tglobal\tnone\n"
    expected += "val\tscp_0\tx\tvariable\tint\tglobal\tx\tx\n"
    assert(sym_alloc(input) == expected)
```

This is clean. The plan even *shows* test code, which puts it ahead of most others.

However, the text-format intermediate representation introduces **incidental complexity** in tests. Every test must construct tab-separated strings with correct column alignment. A missing tab or extra space silently breaks the parser. Compare with the TDD plan where a test constructs an `IR_Cmd` object programmatically — no string parsing needed.

### Dependency Injection: 6/10

The pipeline orchestrator uses `@export var stage_*` nodes. This is good — you can swap stages by changing which node is wired. But the `transform(input: String) -> String` interface is inflexible. What if a stage needs configuration beyond the input string? What if you want to inject a different template file for testing?

The template file itself is a hardcoded path (`templates/templates.tsv`). In a test, you'd need a real file on disk, or you'd have to mock the file system.

### Tests as First-Class Citizens: 6/10

The plan shows test code (big plus) and describes testing stages in isolation. It explicitly notes that "each stage can be tested independently." This shows the author values testability.

But the tests are **after-the-fact verification**, not test-first design. The plan doesn't prescribe writing tests before implementation. The tests shown are "given this input, assert that output" — which is good, but it's not red-green-refactor.

### Incremental Testable Increments: 8/10

The pipeline architecture is **perfect for incremental testing**. Each stage has a well-defined input and output. You can:

1. Test `ir2flat` with a known YAML string
2. Test `sym_alloc` with a known flat IR string
3. Test `templ_expand` with a known flat IR + template string
4. Test `reg_resolve` with known semi-resolved assembly
5. Test `line_asm` with known resolved assembly

Each stage builds on the previous one, but each is independently testable. This is exactly the kind of incremental confidence TDD advocates.

### Confidence Through Testing: 7/10

The text-stream model gives high confidence because you can inspect intermediate outputs. You can run any stage in isolation and see exactly what it produces. There's no hidden state.

But the confidence is limited by the **fragile text format**. The plan's tab-separated intermediate format is not validated — a malformed line could cause silent corruption. Tests would need to cover many format edge cases (empty fields, quoted fields, Unicode, etc.).

### TDD Critique Summary

| Strength | Weakness |
|----------|----------|
| Pure text filters are easy to test | Tab-separated format adds parsing overhead to tests |
| Pipeline supports incremental stages | Template file path is hardcoded |
| Plan shows actual test code | Tests are verification, not test-first |
| No shared mutable state | `transform(String) -> String` interface is too rigid |
| Stages can be composed/reordered | No error path testing strategy |

**Bottom line**: The Unix plan is a **close second** to the TDD plan in terms of practical testability. If I had to choose a non-TDD plan to work with, this would be it. The text-stream model is simple, testable, and composable. The main gaps are: no red-green-refactor cycle, no dependency injection for configuration, and a fragile text format. With those addressed, it would be TDD-compatible.

---

## 5. XP (Extreme Programming) Plan

### File: [`./plans/xp_codegen_plan.md`](./plans/xp_codegen_plan.md)

### Verdict: **Best Non-TDD Plan — Close Cousin**

### Testability: 8/10

The XP plan decomposes the codegen into four standalone passes (Slot Allocator, Pattern Matcher, Slot Resolver, Emitter), each a class with a single public method. These are testable in isolation:

```gdscript
func test_slot_allocator_assigns_globals_for_global_scope():
    var ir = make_single_var_ir("x")
    var allocator = SlotAllocator.new()
    allocator.allocate(ir)
    var var_x = ir.code_blocks["global"].code[0].bindings["dest"]
    assert_eq(var_x.storage.type, "global")
```

The plan organizes tests at three levels: **acceptance** (golden-file comparison), **pass-level** (unit tests per pass), and **mutation** (tests that fail when templates are removed). This is a well-thought-out test strategy.

### Dependency Injection: 7/10

The passes are classes that can be instantiated independently. The `PatternMatcher` takes a `template_table` parameter. The `SlotAllocator` is a standalone class. Dependencies are explicit: `SlotResolver.resolve(frag, all_syms)` — you pass in the data it needs.

The acceptance test compares old vs. new output, which is a form of regression testing but not true dependency injection. The plan's "collective code ownership" section correctly identifies each file's responsibility.

### Tests as First-Class Citizens: 8/10

The XP plan has the **second-best test strategy** of all plans (after the TDD plan itself). It defines:

- Three levels of tests (acceptance, pass-level, mutation)
- Test code snippets for each level
- A sprint-by-sprint migration that keeps tests green
- "Bit-exact comparison test" as a safety net
- Mutation tests for collective ownership safety

The plan explicitly states: "Each pass is testable in isolation (feedback)." This shows the author understands that tests are for *feedback*, not just verification.

### Incremental Testable Increments: 9/10

The incremental migration strategy is this plan's strongest feature. It replaces **one IR command at a time**, keeping the old `generate_cmd_*` functions as fallback:

> "We do **not** flip a switch. We replace one IR command at a time."

Each sprint has a clear goal and a "test: same output" criterion. The plan maps out 6 sprints, each producing a working system that passes all existing tests. This is exactly how a TDD practitioner would approach a refactoring.

### Confidence Through Testing: 8/10

The combination of golden file regression tests, pass-level unit tests, and mutation tests provides strong confidence. The acceptance test that runs all `res/data/*` programs through both old and new codegens and compares output is a powerful safety net.

The risk table explicitly addresses "breaking change during migration" with the mitigation: "Each sprint keeps the old `generate_cmd_*` as fallback. Bit-exact comparison test."

### TDD Critique Summary

| Strength | Weakness |
|----------|----------|
| Three-tier test strategy (acceptance, unit, mutation) | Tests compare against *old* output, not against *spec* |
| Incremental one-command-at-a-time migration | No red-green-refactor cycle shown |
| Explicit sprint-by-sprint testing criteria | Mutation test is described but not implemented |
| YAGNI — explicitly defers unnecessary features | No dependency injection for test doubles |
| "Tests are for feedback" mindset | Acceptance test depends on old codegen being correct |

**Bottom line**: The XP plan is the **closest to TDD** of all nine plans. Its author clearly values testing, incremental delivery, and continuous feedback. The main differences from pure TDD are: (1) tests verify against old output rather than against a specification, and (2) there's no explicit red-green-refactor cycle. If this team adopts TDD practices, they'd need to shift from "same output as old codegen" to "output matches specification" — but the infrastructure is already there.

---

## 6. Design Patterns (GoF OOP) Plan

### File: [`./plans/design_patterns_codegen_plan.md`](./plans/design_patterns_codegen_plan.md)

### Verdict: **Over-Engineered and Under-Tested**

### Testability: 4/10

The plan introduces **8 GoF patterns**: Command, Visitor, Strategy, Template Method, Composite, Decorator, Prototype, Chain of Responsibility. Each pattern adds indirection. Testing a single codegen path requires instantiating:

- An `IrCommand` (e.g., `MovCommand`)
- An `AssemblyEmitterVisitor` (with its own dependencies)
- A `RegisterAllocator` (one of several strategies)
- A `StorageAllocator`
- An `OperandResolver` (with a chain of handlers)
- A `TemplateProvider`
- An `AssyEmitter` (possibly wrapped in decorators)

That's 7+ objects to construct for one test. The Visitor pattern, while elegant for adding new operations, makes testing painful — you can't test `visit_mov` in isolation because the visitor is a monolithic interface with 12+ methods.

### Dependency Injection: 6/10

The plan explicitly uses Strategy pattern for injectable algorithms (`RegisterAllocator`, `StorageAllocator`, `TemplateProvider`). The Decorator pattern allows dynamic composition of emitters. The Command pattern encapsulates IR commands as objects. These are good DI practices.

But the Visitor pattern is an anti-pattern for testability. The `AssemblyEmitterVisitor` has 12+ `visit_*` methods that all share internal state. You cannot test `visit_mov` without also implementing `visit_op`, `visit_if`, etc. (because the visitor interface requires all methods). You can't easily mock a visitor for testing a command.

### Tests as First-Class Citizens: 2/10

The plan does not mention testing. Not once. It has a "Design Review Checklist" and "Sign-Off" sections (copied from Waterfall), but no test strategy, no test file structure, no test examples.

This is particularly ironic for a plan built on GoF patterns. The GoF book itself is about designing for *change* and *extensibility*, but the plan misses that testability is the most important form of extensibility.

### Incremental Testable Increments: 3/10

The plan is presented as a complete design — all 22 files, all 8 patterns, all at once. There's no incremental path. To test anything, you need most of the infrastructure in place: you need the `TemplateRegistry`, the `RegisterAllocator`, the `OperandResolver` chain, and the `AssemblyEmitterVisitor` all wired together.

The Template Method pattern (`InstructionGenerator`) is the closest thing to incremental testability, but the plan doesn't suggest starting with a base generator and adding patterns one at a time.

### Confidence Through Testing: 3/10

The plan provides no confidence because it provides no tests. Despite having the most architectural diagrams and the most elaborate class hierarchy, it's essentially an untestable design. The multiple layers of indirection (Decorator wrapping, Visitor dispatch, Chain of Responsibility) make debugging failures extremely difficult.

If a test fails in a system with 5 decorators wrapping an emitter, you have to unwrap the onion to find where the bug is. The plan offers no guidance on how to test at each layer.

### TDD Critique Summary

| Strength | Weakness |
|----------|----------|
| Explicit strategy interfaces for DI | Zero test strategy or test examples |
| Decorator pattern separates concerns | Visitor pattern makes unit testing difficult |
| Command pattern encapsulates IR ops | 7+ objects needed per test |
| Composite pattern enables tree assertions | No incremental implementation path |
| Template Method defines generation skeleton | Over-engineering before validated learning |

**Bottom line**: This is the textbook example of **architecture astronautics** from a TDD perspective. The author identified all the ways the system *might* need to change and designed patterns for each one — but forgot that the most important change is the one you'll make when you discover your design is wrong. TDD teaches us to write the test first, then write just enough code to pass it. This plan writes all the code first and never mentions tests.

---

## 7. Literate Programming Plan

### File: [`./plans/literate_codegen_plan.md`](./plans/literate_codegen_plan.md)

### Verdict: **Documentation is Not a Substitute for Tests**

### Testability: 5/10

The plan's pipeline (Template Table → Pattern Matcher → Slot Resolver → Emitter) is similar to the XP plan and is reasonably testable. Individual components like `PatternMatcher` and `SlotResolver` have single responsibilities.

The `RegisterAllocator` is extracted as a separate class, which is good for testing:

```gdscript
var _in_use = {}
func alloc() -> String:
    for reg in REGS:
        if not _in_use.get(reg, false):
            _in_use[reg] = true
            return reg
    return ""
```

However, this allocator is **mutable** — it mutates `_in_use` as a side effect. Tests must call `reset()` between cases or create a new instance. The TDD plan's allocator is an immutable state machine that threads state through return values, which is more testable.

### Dependency Injection: 4/10

The `PatternMatcher` takes a `_templates` dictionary in its constructor — good. But the `SlotResolver` takes `_all_syms` and creates its own `_reg_alloc` internally — you cannot inject a different register allocator for testing.

The plan uses `preload` for template data (`var _templates = preload("res://template_defs.gd")`), which means templates are loaded at compile time, not injectable at runtime.

### Tests as First-Class Citizens: 3/10

The plan mentions testing in passing: "Each pass is testable in isolation" and "This separation means we can test register allocation without invoking the full codegen pipeline." But it provides **no test examples**, no test file structure, no test strategy.

The literate programming philosophy is "programs are written for humans first." From a TDD perspective, tests ARE the documentation written for humans. A literate program that doesn't include tests is missing its most important human-readable content.

### Incremental Testable Increments: 4/10

The plan describes a linear pipeline, which supports incremental testing in theory. But it doesn't prescribe an implementation order. It presents the entire design as a complete document — you'd have to extract the order yourself.

The "tangling" process extracts all code into files at once. There's no concept of "implement and test stage 1, then tangle stage 2." Tangling is an all-or-nothing extraction.

### Confidence Through Testing: 4/10

The extensive prose and code examples make the design *understandable*, but understanding is not confidence. A reader can see what the code *intends* to do, but without tests, there's no proof it actually works.

The plan admits this in its section on `_resolve_storage`: it has a default case that returns `"ERROR"`. Without a test, that error path will only be discovered at runtime. With TDD, you'd write `test_unknown_storage_type_returns_error()` first.

### TDD Critique Summary

| Strength | Weakness |
|----------|----------|
| Well-documented design intent | No test examples or test strategy |
| Pipeline architecture supports isolation | Register allocator is mutable (bad for testing) |
| Pattern matcher takes injectable templates | SlotResolver creates its own dependencies |
| Named slots self-document operation semantics | Tangling is all-or-nothing (no incremental extraction) |
| Honest about error-returning paths | Prose is not a substitute for passing tests |

**Bottom line**: The Literate Programming plan is beautiful to read but empty where it counts — tests. Donald Knuth's original literate programming vision included tests as an integral part of the documentation (he called them "proofs of correctness"). This plan misses that crucial element. The documentation is excellent, but without a test suite, I have no confidence the code works.

---

## 8. Agile/Scrum Plan

### File: [`./plans/agile_codegen_plan.md`](./plans/agile_codegen_plan.md)

### Verdict: **Process Without Practice**

### Testability: 6/10

The plan's architecture (flat symbol table, bitfield register allocator, pre-compiled template bytecode, buffered assembly output) is similar to the DOD plan and has similar testability issues. Static arrays, `PackedByteArray` output, and batch processing make isolation difficult.

However, the plan's "Golden File Regression Suite" (story E-1) and "Test Oracle" (story A-3) are explicit testing stories with acceptance criteria. This is more than most plans offer.

### Dependency Injection: 3/10

The plan mentions `TemplateRegistry.load_from_yaml(path)` which takes a file path — testable, but still file-dependent. The register allocator as a bitfield is a static `var` — not injectable. The emit interpreter operates on global state.

The architecture diagram shows "Template Registry → Compiled templates → Emit Engine" with no interfaces between them.

### Tests as First-Class Citizens: 5/10

The plan has **testing stories** in its backlog:

- A-3: Write a Test Oracle (8 story points, P0)
- E-1: Golden File Regression Suite (5 story points, P0)
- E-2 through E-6: Various test stories (total 14 story points)

This is better than most plans. Testing is explicitly budgeted and prioritized. The Definition of Done requires "≥80% line coverage" for new code.

But — crucially — **testing is in Epic E ("Validation & Hardening")**, which happens in Sprints 4–5. Testing is treated as a *phase* at the end, not an *integral practice* from Sprint 0. The golden file oracle is written in Sprint 0 (story A-3), but the actual unit tests for the template parser (story B-1 tests) are only mentioned as "unit tests," not planned as stories.

### Incremental Testable Increments: 5/10

The sprint structure provides incremental *delivery*, but not necessarily incremental *testing*. Each sprint delivers working code that passes the golden file oracle, but:

1. The golden file oracle only compares against *old* output, not against a specification
2. The unit tests for each component are scheduled *after* the component is built
3. There's no red-green-refactor cycle within a sprint

The plan's risk table acknowledges "Template parser complexity underestimated" but mitigates with "Spike in Sprint 0" — not with "write tests first."

### Confidence Through Testing: 5/10

The golden file regression suite provides good confidence that the new codegen produces the same output as the old one. But "same as old" is a weak specification — it assumes the old codegen is correct, which the TDD plan's diagnosis shows is not true (the old codegen has untestable design).

The error recovery testing (story E-3) is good, but it's a P2 (Could) story — likely to be cut when deadlines loom.

### TDD Critique Summary

| Strength | Weakness |
|----------|----------|
| Explicit testing stories with point estimates | Testing is a late-phase activity (Sprint 4-5) |
| Golden file oracle as regression safety net | Tests compare against old output, not specification |
| Definition of Done includes coverage threshold | No unit tests written before implementation |
| Risk table acknowledges complexity | Static arrays hinder test isolation |
| Sprint structure provides incremental delivery | No red-green-refactor cycle |

**Bottom line**: The Agile/Scrum plan gets *process* right but *practice* wrong. It has the ceremonies (sprint planning, daily standup, retrospectives) and the artifacts (golden files, story points, velocity tracking) but misses the core TDD practice of writing tests first. Testing is a phase, not a rhythm. If this team adopted TDD within their Scrum framework, they'd have a powerful combination. As-is, they have project management without engineering discipline.

---

## 9. Waterfall / BDUF Plan

### File: [`./plans/waterfall_codegen_plan.md`](./plans/waterfall_codegen_plan.md)

### Verdict: **Antithesis of TDD**

### Testability: 2/10

The plan is a 1705-line specification document with 22 implementation files, a requirements traceability matrix, sign-off sections, and a change control board. But **zero test code**.

The test strategy (Phase 4) is a separate phase that comes *after* implementation. The "Test Case Catalog" is a list of test IDs linked to requirements — it's a traceability exercise, not a test strategy. There are no test implementations, no test examples, no test infrastructure.

The architecture itself is procedural (pipeline stages as functions), which is *potentially* testable, but the plan doesn't propose testing them in isolation.

### Dependency Injection: 2/10

The plan mentions `var allocator: AllocatorStrategy` — one pluggable interface — but the rest of the pipeline is hardcoded. The `TemplateEngine`, `CommandRegistry`, and `ControlFlowHandler` are concrete classes with no interfaces.

The "Sign-Off" sections between phases are the plan's idea of quality control: review documents, not tests.

### Tests as First-Class Citizens: 0/10

**Tests are not first-class citizens. They are fourth-class citizens.** Testing is Phase 4 of 5, happens after all implementation is done, and is a "Verification Plan" — a checklist, not a practice.

The plan's requirements traceability matrix has columns for: Req ID, Source File, Test Case ID, Design Component, Implementation File. The "Test Case ID" column is populated with IDs like "TC-OP-01", but no test case for any ID is ever written. They're placeholders for a future phase.

### Incremental Testable Increments: 1/10

The plan is strictly sequential: Phase 1 (Requirements), Phase 2 (Design), Phase 3 (Implementation), Phase 4 (Testing), Phase 5 (Maintenance). You cannot test anything until Phase 4. If a design flaw is discovered in Phase 4, you must go back to Phase 2 through the Change Control Board.

The "Implementation Order" in Phase 3 specifies the order files should be written, but there's no testing between files. You'd write all 22 files, then test them all at once.

### Confidence Through Testing: 1/10

The plan provides confidence through **documentation review**, not testing. The "Design Review Checklist" and "Sign-Off" sections are attempts to ensure quality through meetings and signatures. This is the 1970s approach to quality assurance, and it fails as often today as it did then.

The "Change Control Board" (§5.1) is explicitly designed to make changes expensive — the opposite of what you want when tests reveal a design flaw.

### TDD Critique Summary

| Strength | Weakness |
|----------|----------|
| Comprehensive requirements documentation | Testing is a separate phase after implementation |
| Formal sign-off process | Zero test examples or test code |
| Requirements traceability matrix | No feedback loop — flaws found late |
| Risk register acknowledges issues | Change Control Board makes fixes expensive |
| Phase-gate structure ensures completeness | 22 files must be built before any can be tested |

**Bottom line**: This is the **least TDD-compatible plan** by a wide margin. It treats testing as a verification activity at the end of a sequential process, not as a design activity that drives development. Every principle of TDD — test first, incremental feedback, emergent design, refactoring courage — is violated. If this plan were followed, the codegen would take months to deliver, would have unknown correctness until the very end, and would be extremely costly to change when (not if) requirements evolve.

---

## 10. Lisp Macro Plan

### File: [`./plans/lisp_macro_codegen_plan.md`](./plans/lisp_macro_codegen_plan.md)

### Verdict: **Powerful but Opaque — Hard to Test**

### Testability: 3/10

The plan's core insight — code as data, macros as transformers — is powerful, but testing macro-expanded code is notoriously difficult. The plan requires you to test at multiple levels:

1. **The pattern matcher**: Does `match(pattern, sexpr)` produce correct bindings?
2. **The quasiquote expander**: Does `expand_qq(template, bindings)` produce the right sexpr?
3. **The macro function**: Does `macro_fn.call(sexpr, env)` produce the right assembly sexpr?
4. **The serialize pass**: Does `serialize(sexpr)` produce the right text?
5. **The composed pipeline**: Do all passes together produce the right assembly?

Each level is testable in theory, but debugging failures across levels is painful. If a macro produces wrong assembly, is it the pattern matching, the quasiquote expansion, the macro definition, the storage pass, the register pass, or the serialize pass? The plan offers no guidance on isolating failures.

The `gensym` (generated symbol) mechanism makes tests **non-deterministic**. A test that asserts `jz if_else_42` might fail on the next run because `gensym` produces `if_else_43`. The plan doesn't address how to test with generated labels.

### Dependency Injection: 5/10

The macro table is a `const` Dictionary — hardcoded. But individual macros are `Macro` objects with injectable `expander` callables. The passes are `MacroPass` objects with addable rules. This is reasonably composable and injectable.

The `env` object carries all state (register allocation, label generation, symbol table). This is a dependency injection *context* pattern — not clean DI, but functional.

### Tests as First-Class Citizens: 2/10

The plan does not mention testing. It discusses "comparison: current vs. macro-driven" and claims "Pipe data through pure functions" under "Why testable?", but provides no test strategy, no test examples, no test structure.

The plan's "Layer 0 → Layer 4" bottom-up approach is the opposite of test-first. You build all the infrastructure, then build on top of it. You can't test Layer 3 until Layers 0-2 are complete.

### Incremental Testable Increments: 3/10

The plan describes **passes** (template expansion → storage allocation → register allocation → label resolution → serialization) which could be tested incrementally. But the pass structure requires the full S-expression infrastructure at each level.

The bottom-up layer approach means you must build the macro engine (pattern matcher + quasiquote expander) before you can test any template. That's a significant upfront investment before you get any test feedback.

### Confidence Through Testing: 3/10

Macro systems are powerful but **brittle**. A macro that looks elegant in definition can produce surprising output in edge cases. Without tests for each macro, you're relying on the author's mental model of what the macro expands to.

The `PatternVar` and `QQUnquote` classes add metaprogramming complexity. If a pattern variable constraint fails silently, the macro returns an empty array (`[]`), which will cause cryptic errors downstream. The plan explicitly returns `[]` on pattern match failure — a silent failure mode that tests should catch.

### TDD Critique Summary

| Strength | Weakness |
|----------|----------|
| Code-as-data is philosophically clean | Macro expansion is hard to debug across levels |
| Passes are composable transformations | `gensym` makes tests non-deterministic |
| Macro table is declarative data | Bottom-up layers delay test feedback |
| Pattern matching is generic and reusable | Silent failures on pattern mismatch |
| Homogeneous S-expression representation | High metaprogramming complexity |

**Bottom line**: The Lisp Macro plan is intellectually elegant but practically difficult to test. Macro systems are famously powerful and famously hard to debug. The plan offers no testing strategy, no deterministic test approach, and no guidance on isolating failures across the multi-pass pipeline. In a GDScript codebase (not a Lisp with a rich macro ecosystem), the metaprogramming overhead is not justified. The same data-driven results can be achieved with simpler, more testable patterns.

---

## 11. Final Verdict: Ranked by TDD Fitness

| Rank | Plan | Test Score | Why |
|------|------|------------|-----|
| **1** | **TDD (this plan)** | **10/10** | Test-first design, pure functions, DI throughout, 12 incremental increments, 100% coverage goal |
| **2** | **XP** | **8/10** | Three-tier test strategy, incremental migration, YAGNI, strong feedback loop |
| **3** | **Unix Philosophy** | **7/10** | Pipeline of pure text filters, testable in isolation, explicit test examples |
| **4** | **Functional Purity** | **6/10** | Pure functions are inherently testable, but no test strategy exists |
| **5** | **Literate Programming** | **4/10** | Well-documented but no test examples; tests seen as separate from documentation |
| **6** | **Agile/Scrum** | **4/10** | Testing stories exist but are late-phase; process over practice |
| **7** | **Design Patterns** | **3/10** | Over-engineered abstraction layers make testing painful; no test strategy |
| **8** | **Lisp Macro** | **3/10** | Powerful but opaque; non-deterministic `gensym`; no test strategy |
| **9** | **Data-Oriented** | **2/10** | Static global state makes testing impossible; all-or-nothing batch pipeline |
| **10** | **Waterfall/BDUF** | **1/10** | Testing is a separate phase after implementation; no feedback loop |

### Key Takeaways

1. **The XP plan is my closest ally.** If I had to collaborate with another persona, it would be the XP Advocate. Our values align: incremental delivery, continuous feedback, courage to refactor, and YAGNI. The main gap is that XP tests retroactively (comparing against old output) while TDD tests prospectively (against specification).

2. **The Unix Philosophy plan is the most practical runner-up.** Its text-stream pipeline is simple, testable, and composable. The main improvements needed are: injectable configuration, a less fragile intermediate format, and a red-green-refactor cycle.

3. **The Functional Purity plan has the right architecture but wrong process.** The design is almost perfectly testable, but without a test strategy, that testability is wasted potential. I'd happily pair with a Functional Purity advocate to add tests to their design.

4. **The Waterfall plan is the enemy.** It treats testing as an afterthought, makes change expensive, and delays feedback until the end. Every principle of TDD exists to prevent exactly the problems that Waterfall creates.

5. **The Data-Oriented plan repeats the original sin.** The current [`codegen_md.gd`](./codegen_md.gd) is untestable because of global mutable state. The DOD plan replaces Dictionary globals with static array globals — different data structures, same problem.

### A Challenge to the Other Personas

Write a test. Just one. Pick the smallest function in your plan and write a test for it. If you can't — if you find yourself needing to set up half the system just to test one function — then your design has a testability problem that will manifest as bugs, regression fears, and slow development.

The TDD plan has 150+ tests across 12 increments. Every single one can be written before any implementation code exists. That's the standard.
