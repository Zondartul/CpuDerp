# A Literate Programming Critique of the Other Nine Plans

> *"Instead of imagining that our main task is to instruct a computer what to do, let us concentrate rather on explaining to human beings what we want a computer to do."* — Donald Knuth

**Critic**: Literate Programming Advocate
**Date**: 2026-06-27

---

## 1. Overview of Evaluation Criteria

From the literate programming perspective, a plan document is judged by how well it serves as a **communication artifact between humans**. The following criteria matter:

| Criteria | What We Look For |
|----------|------------------|
| **Human communication** | Does the document explain *why* before *what*? Does it tell a story? |
| **Documentation as first-class** | Is the explanation the primary artifact, or is it a wrapper around code/data? |
| **Interleaving explanation & code** | Are code blocks embedded within narrative prose, or separated into appendices? |
| **Tangling/weaving capability** | Could the code be extracted from the document? Is the document the source of truth? |
| **Readability of the plan itself** | Is the document pleasant and enlightening to read, or is it a reference manual? |

What follows is a constructive critique of each plan. I evaluate each on its own terms first, then from the literate programming perspective.

---

## 2. Critique: Functional Purity Codegen Plan

**File**: [`plans/functional_purity_codegen_plan.md`](plans/functional_purity_codegen_plan.md)

### What it does well

The plan has a clear intellectual through-line: identify purity violations, then fix them. The diagnosis table (Section 1) is effective because it maps concrete locations to abstract principles. The mathematical type signatures (`Codegen : IR_Program → AssemblyResult`) provide a formal specification that is unambiguous.

The plan correctly identifies that the current codegen's state entanglement is a *communication* problem as well as a *correctness* problem — when a reader cannot trace data flow through a function, they cannot understand it.

### Where it falls short

**The plan reads as a formal proof, not as an explanation to humans.** Mathematical notation is used where prose would serve better. The `expand_template` function on line 313 is defined purely, but the reader is never told *why* a template expansion needs to be pure — the reasoning is assumed rather than narrated.

**Documentation is viewed as a byproduct of types.** The claim on line 674 that "The Template table IS the documentation of the IR→assembly mapping" is revealing. In the functional purity view, the types and data structures are self-documenting. But they are not. A template record `{"type": "direct", "pattern": ["MOV"], "body": "mov ^{2}, ${1};\n"}` tells you *what* the mapping is, but not *why* `^` denotes store and `$` denotes load, nor what alternatives were considered, nor how this mapping evolved from the existing code.

### Literate Programming Verdict

The functional purity plan is an excellent **design document**, but it is not a **literate program**. It tells the computer what to do (through pure function signatures) but does not concentrate on explaining to human beings. The mathematics is a barrier, not a bridge.

**Score: 3/10** — Formal rigor at the expense of human communication.

---

## 3. Critique: Data-Oriented Codegen Plan

**File**: [`plans/data_oriented_codegen_plan.md`](plans/data_oriented_codegen_plan.md)

### What it does well

This plan has a strong internal consistency. Every design decision flows from the central principle: respect the memory hierarchy. The cache-line analysis (Section 10) is enlightening — it shows exactly which data structures belong in L1 cache and which in RAM. The SoA (Structure of Arrays) layout is argued on concrete, measurable grounds.

The plan also has the best diagrams (the "Data Flow" pipeline on line 52 and the "Memory Layout Summary" on line 680). These are genuinely helpful for understanding the architecture.

### Where it falls short

**The plan optimizes for machine understanding, not human understanding.** The entire argument is framed around CPU cache behavior — L1, L2, prefetching, cache lines. These are real concerns, but they are concerns of the *target machine*, not of the *human reader*. The literate programmer asks: does my reader need to understand cache hierarchies to understand the codegen? The answer is no.

**No narrative of design evolution.** The plan states *what* the flat arrays look like (Section 4) but not *why* they evolved from the current object-oriented structure. A literate critique would interleave the old code with the new, showing each transformation and explaining its motivation.

**The pre-compiled template bytecode (Section 5) is particularly anti-literate.** Converting templates from readable strings into opcode integers (`EmitOp.TEXT`, `EmitOp.LOAD`, etc.) makes the system faster but opaque. A literate programmer would keep the human-readable form as the source of truth and treat the bytecode as a compilation artifact.

### Literate Programming Verdict

The data-oriented plan is an excellent **performance specification**, but it treats the human reader as an optimizer, not as a learner. The document itself is dense, technical, and joyless to read. No literate programmer would accept "and then compile it to integers" as a substitute for explanation.

**Score: 4/10** — Technically impressive, humanistically impoverished.

---

## 4. Critique: Unix Philosophy Codegen Plan

**File**: [`plans/unix_philosophy_codegen_plan.md`](plans/unix_philosophy_codegen_plan.md)

### What it does well

This plan has the **best narrative flow** of any plan so far. The pipeline diagram (Section 3) tells a clear story: IR flows through six stages, each doing one thing. The worked example (Section 5) traces a single expression through all six stages, showing the exact text at each step. This is exactly the kind of interleaved explanation that literate programming values.

The plan also uses **text as a universal interface**, which aligns with literate principles. When every stage reads and writes text, the pipeline is inspectable at every point — you can `tee` into it, debug it, understand it.

### Where it falls short

**The template format is still text-with-markers, not explanation-with-code.** The TSV file (`templates/templates.tsv`) is a data file, not a literate document. There is no explanation of *why* a particular template expands the way it does — it is simply machine-readable.

**The pipeline, while well-structured, is described mechanistically.** Each stage's section reads like a man page: input format, output format, algorithm. There is no "why" section. A literate description would say: "Here is why we separate storage allocation from template expansion — because the two concerns change at different rates and for different reasons."

**No tangling/weaving.** The plan is a specification that would be written and then implemented separately. The document is not the source of truth; the implementation is.

### Literate Programming Verdict

The Unix plan comes closest to literate ideals in its emphasis on **composability** and **inspectability**. The stage-by-stage data flow example is genuinely educational. But the templates themselves are foreign to literate ideals — they are machine-consumed data, not human-explained code.

**Score: 6/10** — Best narrative flow so far, but templates are opaque data, not illuminated code.

---

## 5. Critique: TDD-Driven Codegen Plan

**File**: [`plans/tdd_codegen_plan.md`](plans/tdd_codegen_plan.md)

### What it does well

The plan has the most **concrete, executable specification** of any plan. Each increment starts with a failing test, then shows the minimal code to pass it. This is essentially a literate program written in tests: the tests are the explanation, and the code is extracted from them.

The dependency injection architecture (Section 7) is clearly motivated and well-documented. The test-fixture format (Section 8) is clean.

### Where it falls short

**The tests are the documentation, but they are not a narrative.** The plan reads as a sequence of test cases, not as an explanation of the codegen design. A literate reader wants to know *why* MOV needs a dest and src slot, not just that `test_expand_mov_imm_to_global` asserts specific output.

**There is no big picture.** The plan is 1,576 lines of test-driven increments, but nowhere does it step back and say: "Here is the architecture, here is why it is structured this way, here is how the pieces fit together." The literate principle is to explain the forest, not just catalogue the trees.

**The template table (Section 5) is described as pure data, but the data is not explained.** A reader sees `"MOV": {"pattern": ["MOV"], "body": "mov ^2, $1;\n", "size": 8}` but is never told what `^2` and `$1` mean, or why the slot numbering starts at 1, or what alternatives were considered.

### Literate Programming Verdict

The TDD plan is an excellent **test specification**, and it comes closer to literate ideals than most because the tests serve as both documentation and validation. But tests are a limited form of explanation — they tell you *what* the code does, not *why* it was designed that way.

**Score: 5/10** — Tests as documentation is a noble goal, but not a substitute for narrative explanation.

---

## 6. Critique: XP-Driven Codegen Plan

**File**: [`plans/xp_codegen_plan.md`](plans/xp_codegen_plan.md)

### What it does well

The XP plan is **refreshingly concise** (400 lines vs. 1,500+ for TDD or Waterfall). It follows its own principles: YAGNI is evident in what it does *not* specify. The incremental migration strategy (Section 6) is the most practical of any plan — six sprints, each replacing one piece.

The template format (Section 4) with `"out":` as an array of lines is clean and readable.

### Where it falls short

**The plan is too terse to be a literate document.** A literate program does not just state the design; it *narrates* the design. The XP plan states *what* each pass does (Section 5) but not *why* the pass exists, *how* it interacts with other passes, or *what* the design alternatives were.

**The focus on "simplest thing that works" actively works against literate values.** The literate programmer aims for completeness of explanation, not minimalism of expression. The XP plan's "Collective Code Ownership" table (Section 8) lists six files with one-line responsibilities, but never explains how they fit into a coherent whole.

**No tangling/weaving capability.** Like the others, this is a plan to be implemented, not a document from which code is extracted.

### Literate Programming Verdict

The XP plan is the most **pragmatic** of the plans, but pragmatism and literate communication are not the same goal. The plan would be effective for a team that already understands the codegen architecture, but it does not *teach* that architecture to a newcomer.

**Score: 5/10** — Concise and practical, but too sparse to serve as a standalone explanation.

---

## 7. Critique: Design Patterns (GoF OOP) Codegen Plan

**File**: [`plans/design_patterns_codegen_plan.md`](plans/design_patterns_codegen_plan.md)

### What it does well

The plan has the most **comprehensive class catalog** (Section 9: ~30 classes listed). Each class is mapped to a GoF pattern with a clear responsibility. The class diagram (Section 4.1) and sequence diagram (Section 4.2) are thorough.

### Where it falls short

**This is the most anti-literate plan in the set.** The literate programmer asks "what does a human reader need to understand?" The GoF plan asks "which design patterns can I apply?" The result is a document that is heavy on taxonomy and light on explanation.

**The pattern names substitute for understanding.** Saying "register allocation is a Strategy pattern" tells a GoF-literate reader where to file the concept, but does not explain the allocation algorithm, the trade-offs of the linear-scan approach, or how it interacts with the template engine.

**30 files, each tiny and focused, is the opposite of the literate ideal.** Knuth's WEB programs were long, narrative, interleaved documents — not a hierarchy of 30 single-responsibility classes. The GoF approach atomizes knowledge into so many files that no single document tells the whole story.

**Template inheritance (Section 5.2.3), Prototype-based template cloning, and the Mediator pattern** all add layers of indirection that obscure the fundamental flow: IR → template → assembly. A literate programmer would prefer the direct, visible pipeline to the pattern-abstracted one.

### Literate Programming Verdict

The GoF plan is a **design pattern catalog** applied to codegen, not an explanation of the codegen itself. It prioritizes architectural purity over human comprehension. The 30-file structure is the antithesis of the single, weaving-capable literate document.

**Score: 2/10** — The most pattern-heavy, explanation-light plan in the set.

---

## 8. Critique: Agile/Scrum Codegen Plan

**File**: [`plans/agile_codegen_plan.md`](plans/agile_codegen_plan.md)

### What it does well

The plan has the best **project management structure**. The epic breakdown (Section 2) is logical; the sprint plan (Section 4) is well-estimated; the delivery roadmap (Section 5) shows clear milestones.

### Where it falls short

**This is a project management document, not a technical explanation.** The word "template" appears 47 times, but the plan never explains what a template *is* or *why* one design is better than another. Section 9 ("Technical Architecture") is called "Just Enough" — which, from a literate perspective, is "not nearly enough."

**User stories are a poor substitute for design narrative.** "As a ZVM language designer, I can add a new IR command by adding a template entry" is a requirement, not an explanation. It tells you *what* the system should do, but not *why* the template approach works, what the alternatives were, or how to think about the problem.

**The Definition of Done (Section 3) mentions documentation, but the documentation is an afterthought.** "Documentation Updated" means the schema doc is kept in sync — not that the code itself is written as a literate document.

### Literate Programming Verdict

The Agile plan is a **project plan**, not a **design document**. It treats the codegen as a project to be managed rather than as a system to be understood. The literate programmer writes documents that *are* the design; the Scrum master writes documents that *plan* the design. These are different genres, and only the former serves literate goals.

**Score: 1/10** — The plan is about managing the work, not about understanding the work.

---

## 9. Critique: Waterfall / BDUF Codegen Plan

**File**: [`plans/waterfall_codegen_plan.md`](plans/waterfall_codegen_plan.md)

### What it does well

The plan is **comprehensive** — 1,700+ lines covering requirements, design, implementation, verification, and maintenance. The Requirements Traceability Matrix (Section 1.6) maps every requirement to a source, test, and implementation file. The Design Review Checklist (Section 2.9) is thorough.

### Where it falls short

**This is the opposite of literate programming in every conceivable dimension.** Literate programming is about iterative, organic explanation of code as it is written. Waterfall is about freezing all requirements before any code exists.

**Documentation is a frozen contract, not a living artifact.** The sign-off gates (Sections 1.7, 2.10, 3.6, 4.6) are designed to prevent change. The Change Control Board (Section 5.1) exists to make change expensive. Literate programming, by contrast, treats the document as malleable — it is rewritten as understanding deepens.

**The templates are specified in excruciating detail (Section 2.6), but never explained to a human.** Each template entry has `description`, `params`, `assembly`, `size` — but no discussion of *why* `cmp %a, %b;` precedes `mov %a, CTRL;` in the comparison template, or what the trade-offs are between this sequence and alternatives.

**The focus on "measure twice, cut once" is admirable for construction, but wrong for understanding.** In literate programming, you cut (write code) and measure (explain it) simultaneously. The weaving process is not separate from the tangling process — they are the same operation viewed from different angles.

### Literate Programming Verdict

The Waterfall plan is a **masterpiece of process documentation**, but it fundamentally misunderstands the relationship between code and explanation. It treats the design as something to be specified before implementation, rather than as something to be discovered through explanation.

**Score: 1/10** — The most rigid, change-resistant plan. The very idea of a "frozen" design is anathema to literate ideals.

---

## 10. Critique: Lisp/Macro-Driven Codegen Plan

**File**: [`plans/lisp_macro_codegen_plan.md`](plans/lisp_macro_codegen_plan.md)

### What it does well

**This plan has the most philosophical affinity with literate programming.** Both traditions believe that code should be readable data structures, not opaque syntax. The Lisp plan's emphasis on **homoiconicity** (Section 2.1: "Code is data, data is code") resonates with the literate ideal that code should be embedded in explanation, not the other way around.

The **bottom-up architecture** (Section 2.3) — building from sexpr primitives to the full pipeline — is a natural fit for literate exposition. A literate programmer could present each layer as a chapter, with code blocks building on earlier explanations.

The **macro pipeline** (Section 6) creates inspectable intermediate representations. This is analogous to the literate ideal that each stage of understanding should be visible. The ability to `print(after_pass2)` and see what the register allocator did (Section 10.1) is exactly the kind of inspectability that literate programmers value.

The **template table as pure data** (Section 8.5) is the closest any plan comes to the literate ideal of code-as-declaration. Adding an instruction is adding one dictionary entry — and in a literate document, that entry would be surrounded by explanation.

### Where it falls short

**The plan prioritizes metaprogramming over explanation.** The S-expression machinery (PatternVar, QQUnquote, quasiquote expansion) is fascinating to a Lisp programmer, but it adds cognitive overhead for a reader who just wants to understand the codegen. The literate programmer asks: "does my reader need to understand quasiquotation to understand how MOV is expanded?" The answer is no.

**The GDScript macro DSL is explained, but not narrated.** Section 5.1 shows template entries with `qq([...])` and `pv(...)`, but the reader is never walked through the expansion step by step. A literate treatment would show: "Here is the IR sexpr. Here is the template. Here is the bindings dictionary after matching. Here is the expanded assembly. Now you see how it works."

**The plan is written for Lisp initiates.** Section 4's quasiquote explanation assumes familiarity with Common Lisp's backtick notation. A literate document should be accessible to a broader audience — it should explain the concepts, not assume them.

### Literate Programming Verdict

The Lisp plan is the **most intellectually compatible with literate programming**, but it is not itself a literate document. It shares the values (code as data, inspectability, composable passes) but not the practice (interleaved explanation, narrative flow, human-first exposition).

**Score: 7/10** — Closest in spirit, but too dense with Lisp-specific machinery to serve as a broad explanation.

---

## 11. Summary Ranking

| Plan | Human Communication | Documentation as First-Class | Interleaving Explanation & Code | Tangling/Weaving | Readability | **Total** |
|------|-------------------|------------------------------|-------------------------------|------------------|-------------|-----------|
| **Lisp/Macro** | 6 | 7 | 6 | 5 | 7 | **31/50** |
| **Unix Philosophy** | 7 | 5 | 6 | 3 | 7 | **28/50** |
| **TDD** | 5 | 6 | 5 | 3 | 5 | **24/50** |
| **XP** | 5 | 4 | 5 | 2 | 6 | **22/50** |
| **Data-Oriented** | 4 | 4 | 4 | 2 | 4 | **18/50** |
| **Functional Purity** | 3 | 4 | 3 | 2 | 4 | **16/50** |
| **Design Patterns** | 3 | 3 | 2 | 1 | 3 | **12/50** |
| **Agile** | 2 | 2 | 1 | 1 | 3 | **9/50** |
| **Waterfall** | 2 | 2 | 1 | 1 | 2 | **8/50** |

---

## 12. What Each Plan Can Learn from Literate Programming

### For the Lisp/Macro plan (highest scoring):
Embed your template examples in a narrative. Show the IR coming in, show the macro matching, show the assembly coming out — not as code, but as a story. Your `define_alu_family` metaprogramming (Section 10.2) is precisely the kind of higher-order explanation that literate programming excels at: explain the general pattern, then show the specific instances.

### For the Unix Philosophy plan:
Your worked example (Section 5) is a step in the right direction. Extend it: for each stage, show not just the text transformation, but the *reasoning* behind the transformation. Why does `var_1` become `*var_1` in the global case? Why do args get pushed in reverse? These are the questions a literate treatment would answer.

### For the TDD plan:
The test-first approach inherently documents behavior. To make it literate, add a narrative layer above the tests: a chapter for each component that explains *why* the component exists, *how* it fits into the architecture, and *what* the design alternatives were. Let the tests validate the behavior, but let the prose explain the design.

### For the XP plan:
Your incremental migration strategy (Section 6) tells a story of evolution — this is a literate-friendly structure. Expand each sprint's description to include not just what changes, but *why* it changes and *what* the old approach was. The contrast between old and new is a powerful explanatory device.

### For the Data-Oriented plan:
Your cache-line analysis tells a story about the machine. A literate version would also tell a story about the *reader* — showing how the flat arrays make the code easier to reason about (not just faster to execute). Performance is a valid concern, but it should not be the *only* concern the document addresses.

### For the Functional Purity plan:
The diagnosis table (Section 1) identifies problems that are also communication problems. A literate version would use that table as the backbone of the document, then for each violation show: the old code, explain why it is hard to reason about, then show the new pure version. This before-and-after structure is the heart of literate exposition.

### For the Design Patterns plan:
Reduce the pattern taxonomy and increase the narrative. Instead of "register allocation is a Strategy pattern," write "here is how register allocation works, and here is why the Strategy pattern helps." The pattern names are shortcuts for experienced designers, but they are not explanations for newcomers.

### For the Agile plan:
The product vision statement (Section 1) is the most literate part of this document. Expand it into a full design narrative. The sprint planning and story points are project-management details — they belong in a separate document, not in the design explanation.

### For the Waterfall plan:
The fundamental premise of Waterfall — "freeze the design before writing code" — is incompatible with literate ideals. The closest a Waterfall advocate could come to literacy is to treat the design document itself as a living artifact, updated as understanding deepens, with sign-off gates that validate understanding rather than freeze it.

---

## 13. Conclusion: The Literate Standard

No plan in this set achieves the literate ideal. None of them could be tangled to produce the actual codegen implementation. None of them interleave explanation and code in the way Knuth's WEB programs do — where the code is typeset as part of the prose, and the tangler extracts it mechanically.

The closest are:
1. **Lisp/Macro** — because it treats code as data and values inspectability
2. **Unix Philosophy** — because it traces data flow through concrete examples
3. **TDD** — because it uses tests as executable specifications

But all of them, including my own ([`plans/literate_codegen_plan.md`](plans/literate_codegen_plan.md)), are documents *about* codegen design rather than documents *that are* the codegen design. True literate programming requires a tangling toolchain that extracts source files from the document — and none of these plans provide that.

The irony is not lost on me. I am writing a critique in a markdown file that will be read by humans, but the code it describes will be written in separate `.gd` files. The separation between document and implementation persists. True literacy would require us to embed the GDScript in this very document, with `→` annotations for tangling, and to extract the files from it mechanically.

Until we do that — until we write the code *inside* the explanation rather than alongside it — all of our plans, regardless of their philosophy, remain plans *about* code rather than plans *that are* code. The literate ideal is not just to explain what we want the computer to do, but to make the explanation itself the source of truth.
