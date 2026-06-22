# Implementation Plan: LR(1) DFA Parser with Disk Caching

## 1. Current State Analysis

### 1.1 The Current Parser Architecture

The parser in [`scenes/parser_md.gd`](scenes/parser_md.gd) implements a naive LR(1) shift-reduce parser. Its core loop (lines 52-65) processes tokens one at a time:

```gdscript
for tok:AST in tokens:
    var stabilized = false;
    while not stabilized:
        stabilized = true;
        for ut_rule:Array in lang.rules:
            var rule:Array[String]; rule.assign(ut_rule);
            if rule_matches(stack, tok, rule):
                if rule[-1] == "SHIFT": break;
                apply_rule(stack, rule);
                stabilized = false;
                break;
    if tok.tok_class != "EOF": stack.push_back(tok);
```

### 1.2 Performance Analysis: O(N × R × S)

For each input token, the parser executes:

1. **Inner loop** — iterates over all **105 rules** (the `lang.rules` array), calling [`rule_matches()`](scenes/parser_md.gd:93) for each
2. **`rule_matches()` work** — slices the stack, compares lookahead token, then compares each element of the rule input against the stack (up to ~6 comparisons per rule)
3. **`stabilized` loop** — after each successful reduction, the `stabilized = false` causes the inner loop to restart scanning ALL rules from the beginning

**Quantification for a typical 100-token input:**

| Operation | Count | Approximate Cost |
|-----------|-------|------------------|
| Outer iterations (tokens) | ~100 | Base |
| Rule checks per token (worst case: full scan) | ~105 | ~10,500 total |
| Rule checks per token (avg, after reductions) | ~30-50 | ~3,000-5,000 total |
| Stack comparisons per rule check | 1-6 | ~10,000-50,000 total |
| `stabilized` re-scans after reductions | ~50-200 | Significant multiplier |

**Real-world estimate**: A 100-line MiniDerp program produces ~500-1000 tokens. Each token may trigger 30-105 rule checks, and each reduction restarts the rule scan. This means **50,000-150,000 rule match attempts** per compilation.

### 1.3 The `rule_matches()` Method Detail

[`rule_matches()`](scenes/parser_md.gd:93) does:

1. Extracts lookahead (`rule[-2]`) and rule input (`rule[0..-2]`)
2. Checks `len(stack) >= len(rule_input)` — short-circuit on length mismatch
3. Slices `stack[-len(rule_input)]` — creates a new array
4. Calls [`token_match()`](scenes/parser_md.gd:111) for lookahead AND each input element

[`token_match()`](scenes/parser_md.gd:111) handles three cases:
- `"*"` — wildcard, always matches
- `"/text"` — matches against `tok.text` (e.g., `"/if"` matches when `tok.text == "if"`)
- `"TOKEN_CLASS"` — matches against `tok.tok_class` (e.g., `"IDENT"` matches when `tok.tok_class == "IDENT"`)

### 1.4 The `stabilized` Mechanism

The `stabilized` flag is the **primary performance bottleneck**. Each time a rule is applied (reduction occurs), the flag is set to `false`, causing the inner loop to restart scanning all rules from index 0. This means cascading reductions (e.g., `expr_ident → expr → stmt → stmt_list`) each require a full rule scan.

### 1.5 The `SHIFT` Convention

Rules with result `"SHIFT"` (lines 59, 63, 69, 71, 73-76, 109-110, 115-116 in [`lang_md.gd`](scenes/lang_md.gd)) are "match but don't reduce" rules. They match the current state but explicitly defer reduction. This is the parser's precedence mechanism — when multiple rules could match, the SHIFT rules take priority (checked first in iteration order, and they set `stabilized = true` to prevent further reduction attempts).

### 1.6 Error Handling

- If `len(stack) == 1` after parsing, the result is returned
- If `len(stack) != 1`, a syntax error is reported via [`ErrorReporter`](class_ErrorReporter.gd)
- The `error_code` string is used for error recovery signals

### 1.7 AST Construction

[`apply_rule()`](scenes/parser_md.gd:118) pops N tokens from the stack (N = rule length - 2), reverses them, creates an [`AST`](class_AST.gd) node with `tok_class = rule[-1]`, assigns the popped tokens as `children`, and pushes the new AST node back.

[`linearize_ast()`](scenes/parser_md.gd:129) post-processes the AST to flatten list-type nodes (`stmt_list`, `expr_list`) using [`gather_instances()`](scenes/parser_md.gd:143).

---

## 2. LR(1) DFA Design

### 2.1 Formal Definitions in This Context

**LR(1) Item**: A position within a grammar rule, annotated with a lookahead token type. Represented as:
```
Item = [rule_idx: int, dot_position: int, lookahead: int (token_type_id)]
```

- `rule_idx` — index into `lang.rules` array
- `dot_position` — how many elements of the rule have been matched (0 = start, up to len(rule)-2 = complete)
- `lookahead` — integer token type ID that must follow for this item to be viable

**LR(1) State**: A set of LR(1) items reachable after a sequence of shifts/reductions.

**Goto Function**: `goto[state_id][token_type_id] → state_id` — transition to next state after shifting a token of a given type.

**Action Table**: `action[state_id][token_type_id] → Action` — what to do when seeing a token:
- `{type: "shift", next_state: N}` — push token, go to state N
- `{type: "reduce", rule_idx: N}` — pop rule length tokens, push non-terminal, goto
- `{type: "accept"}` — parsing complete
- `{type: "error"}` — syntax error

### 2.2 Token Type → Integer ID Mapping

All token types appearing in grammar rules must be mapped to integer IDs. These include:

**Terminal token classes** (from tokenizer):
| Token Type | ID |
|-----------|-----|
| `EOF` | 0 |
| `IDENT` | 1 |
| `NUMBER` | 2 |
| `STRING` | 3 |
| `CHAR` | 4 |
| `OP` | 5 |
| `KEYWORD` | 6 |
| `TYPE` | 7 |
| `PREPROC` | 8 |

**Non-terminal types** (used as goto targets after reductions):
| Token Type | ID |
|-----------|-----|
| `start` | 9 |
| `stmt_list` | 10 |
| `stmt` | 11 |
| `block` | 12 |
| `var_decl_stmt` | 13 |
| `assignment_stmt` | 14 |
| ... | ... |

**`/`-prefixed tokens** (matched by `tok.text`):
These are literal text tokens — they DO NOT get their own token type ID. Instead, during tokenization, when a token has `text` matching a `/`-prefixed rule element, we map the rule element to a special ID.

**Key insight**: The `"/"` prefix convention means the parser checks `tok.text`, not `tok.tok_class`. To handle this in the DFA:
- Each unique text value used in `/` rules gets its own virtual token type ID
- At parse time, when checking the input token, we compute: if `tok.text` starts with a `/`-prefixed entry → use that virtual ID; otherwise use `tok.tok_class` ID

**Complete token type ID table** (estimate ~40-50 entries):

```gdscript
# Auto-generated from grammar rules
const TOKEN_EOF         = 0
const TOKEN_IDENT       = 1
const TOKEN_NUMBER      = 2
const TOKEN_STRING      = 3
const TOKEN_CHAR        = 4
const TOKEN_OP          = 5
const TOKEN_KEYWORD     = 6
const TOKEN_TYPE        = 7
const TOKEN_PREPROC     = 8
# Non-terminals start at 9
const TOKEN_start       = 9
const TOKEN_stmt_list   = 10
# ...
# Virtual tokens for /-prefixed rule elements
const TOKEN_SLASH_BRACE_OPEN  = 30   # /{
const TOKEN_SLASH_BRACE_CLOSE = 31   # /}
const TOKEN_SLASH_SEMI        = 32   # /;
const TOKEN_SLASH_VAR         = 33   # /var
const TOKEN_SLASH_EQ          = 34   # /=
# ... etc
```

### 2.3 Handling the `"*"` Wildcard

The `"*"` wildcard represents "match any token not explicitly listed for this state." In the DFA:

- Each state's goto/action for `*` is computed separately
- When building the action table, for each state:
  1. Collect all explicitly handled token type IDs
  2. The `*` action applies to ALL OTHER token types NOT in the explicit set
  3. If multiple items have `*` lookahead, their actions are merged for the "other" set

**Implementation approach**: Store a special `WILDCARD_TOKEN_ID = -1` entry in the action/goto tables that acts as the fallback for any token type not explicitly handled.

### 2.4 Handling `"/"` Prefix Convention

When building the DFA, `/`-prefixed rule elements like `"/if"` are converted to virtual token type IDs (e.g., `TOKEN_SLASH_IF = 35`). 

At parse time, the token type lookup works as follows:

```gdscript
func get_token_type_id(tok: AST) -> int:
    # Check if token text matches any /-prefixed rule element
    if tok.text in slash_token_map:
        return slash_token_map[tok.text]
    # Otherwise use tok_class
    if tok.tok_class in token_type_map:
        return token_type_map[tok.tok_class]
    return TOKEN_WILDCARD
```

`slash_token_map` is a `Dictionary` mapping token text (e.g., `"if"`, `";"`, `"{"`) to virtual token type IDs. This is generated at DFA-build time.

### 2.5 DFA Table Data Structures

```gdscript
# === DFA Data Structure ===

# Structure for serialization
class DFA:
    var states: Array[DFAState]           # Array of state objects
    var token_type_count: int             # Total distinct token type IDs
    var start_state: int = 0              # Always 0
    var errors: Array[String]             # Any DFA generation errors/warnings

class DFAState:
    var id: int
    var goto: Dictionary                   # {token_type_id: next_state_id}
    var action: Dictionary                 # {token_type_id: Action}
    var default_action: Action = null      # Action for * wildcard (fallback)

class Action:
    var type: String                       # "shift", "reduce", "accept", "error"
    var next_state: int = -1               # For "shift"
    var rule_idx: int = -1                 # For "reduce"
    var rule_len: int = 0                  # Number of tokens to pop for reduce
    var rule_result: String = ""           # Non-terminal name for reduce result
```

### 2.6 Serialization Format

Use Godot's `Resource` format (`.tres`) for easy serialization:

```gdscript
# dfa_data.gd - Auto-generated DFA resource
extends Resource
class_name DFAData

var states: Array = []          # Array of Dictionaries
var token_ids: Dictionary = {}  # {token_name: int_id}
var slash_token_ids: Dictionary = {}  # {text_value: int_id}
var rules_hash: int = 0         # Hash of grammar rules for cache invalidation

# Each state Dictionary:
# {
#   "goto": {token_id: next_state_id, ...},
#   "action": {token_id: {type: "shift", next_state: N}, ...},
#   "default_action": {type: "reduce", rule_idx: N} or null
# }
```

**Alternative (more compact)**: Use `PackedInt32Array` + schema for smaller file size. Example:

```gdscript
# Format: [state_count, token_type_count, default_action_for_all, entries...]
# Each entry: [state, token_id, action_type, next_state_or_rule_idx]
```

**Recommendation**: Start with the Dictionary-based approach for clarity. Optimize to packed arrays only if file size becomes an issue.

---

## 3. DFA Generation Algorithm

### 3.1 Overview

The DFA generator walks the grammar rules and constructs the canonical collection of LR(1) states. The algorithm has five phases:

1. **Augment the grammar** — add `start' → start` rule
2. **Compute token type mapping** — assign IDs to all terminals, non-terminals, and `/`-prefixed tokens
3. **Build the canonical collection of LR(1) states** — using closure and goto
4. **Construct action and goto tables**
5. **Serialize and cache**

### 3.2 Augment the Grammar

Add a synthetic start rule so the DFA has a clear accept condition:

```
["start", "EOF", "ACCEPT"]
```

This gives us a single point where `accept` is the action (when we see `EOF` after reducing to `start`).

### 3.3 Closure Computation

```
function closure(items: Set[Item]) -> Set[Item]:
    repeat until stable:
        for each Item = [rule_idx, dot, lookahead] in items:
            if dot < len(rules[rule_idx]) - 2:  # dot not at end
                symbol_after_dot = rules[rule_idx][dot]
                if symbol_after_dot is a non-terminal:
                    for each production_rule with lhs == symbol_after_dot:
                        first_set_of_following = FIRST(rule_suffix + lookahead)
                        for each token in first_set_of_following:
                            new_item = [production_idx, 0, token]
                            add new_item to items
```

**Simplified for our GDScript context**: Since we have a concrete grammar (not a general parser generator), we can hardcode the FIRST set computation. The FIRST set of each non-terminal is the set of terminal tokens that can begin a string derived from it.

FIRST sets for key non-terminals (approximate):
- `FIRST(expr)` = `{IDENT, NUMBER, STRING, CHAR, OP, KEYWORD, TYPE, /(, /[, - (unary)}`
- `FIRST(stmt)` = `{IDENT, NUMBER, STRING, CHAR, OP, KEYWORD, TYPE, /var, /if, /while, /break, /continue, /return, /extern, /func, /include, /(, /[, /{}`
- `FIRST(stmt_list)` = `FIRST(stmt) ∪ {/}}` (empty for epsilon)
- `FIRST(block)` = `{/{}`

### 3.4 Goto Computation

```
function goto(items: Set[Item], symbol: int) -> Set[Item]:
    new_items = empty set
    for each Item = [rule_idx, dot, lookahead] in items:
        if dot < len(rules[rule_idx]) - 2:
            if token_type_id(rules[rule_idx][dot]) == symbol:
                new_item = [rule_idx, dot + 1, lookahead]
                add new_item to new_items
    return closure(new_items)
```

### 3.5 State Construction (Canonical Collection)

```
function build_states():
    start_item = [augmented_rule_idx, 0, TOKEN_EOF]
    start_state = closure({start_item})
    states = [start_state]
    worklist = [0]  # indices of states to process
    
    while worklist not empty:
        state_id = worklist.pop()
        current_state = states[state_id]
        
        # Collect all symbols (token types) that appear after a dot in this state
        symbols = {}
        for item in current_state:
            if item.dot < len(rules[item.rule_idx]) - 2:
                symbol = token_type_id(rules[item.rule_idx][item.dot])
                symbols.add(symbol)
        
        for symbol in symbols:
            new_state = goto(current_state, symbol)
            if new_state not in states:
                states.append(new_state)
                worklist.append(len(states) - 1)
            goto[state_id][symbol] = index_of(new_state in states)
    
    return states, goto
```

### 3.6 Action Table Construction

```
function build_action_table(states, goto):
    for each state_id, state in enumerate(states):
        for item in state:
            if item.dot == len(rules[item.rule_idx]) - 2:
                # Rule is complete — reduce or accept
                if rules[item.rule_idx][-1] == "ACCEPT":
                    action[state_id][item.lookahead] = {type: "accept"}
                else:
                    # Check for SHIFT pseudo-reduction
                    action[state_id][item.lookahead] = {
                        type: "reduce",
                        rule_idx: item.rule_idx,
                        rule_len: len(rules[item.rule_idx]) - 2,
                        rule_result: rules[item.rule_idx][-1]
                    }
        
        for symbol, next_state in goto[state_id].items():
            existing = action[state_id].get(symbol)
            if existing and existing.type == "reduce":
                # Shift/reduce conflict — prefer shift
                # (This matches current parser behavior)
                action[state_id][symbol] = {type: "shift", next_state: next_state}
            elif not existing:
                action[state_id][symbol] = {type: "shift", next_state: next_state}
            # else: both shift — no conflict
        
        # Handle SHIFT pseudo-rules
        for item in state:
            if item.dot < len(rules[item.rule_idx]) - 2:
                symbol_after = token_type_id(rules[item.rule_idx][item.dot])
                rule_result = rules[item.rule_idx][-1]
                if rule_result == "SHIFT":
                    # Force shift — override any reduce action for this symbol
                    if symbol_after in action[state_id]:
                        if action[state_id][symbol_after].type == "reduce":
                            # Ensure shift is taken
                            pass  # goto is already set, which implies shift
```

### 3.7 Conflict Detection and Resolution

The current parser resolves conflicts by:
1. Iterating rules in order (first match wins)
2. Result `"SHIFT"` prevents reduction even when the rule matches

In the DFA, conflicts are detected during action table construction:

| Conflict Type | Resolution | Rationale |
|--------------|-----------|-----------|
| Shift/Reduce | Prefer shift | Matches current `SHIFT` convention |
| Reduce/Reduce | Prefer lower rule index | Matches current "first rule wins" behavior |
| Multiple shifts | First goto wins | Matches current "first match wins" behavior |

**Conflicts to report**: Any resolved conflicts should be logged (via `cprint`) so the developer knows if grammar changes introduce ambiguity.

### 3.8 Step-by-Step Trace

Let's trace a small subset of rules:

```
Rules used for trace:
[0]: ["stmt_list",           "EOF", "start"]       # augmented
[1]: ["stmt_list", "stmt",   "*",   "stmt_list"]
[2]: ["stmt",                "*",   "stmt_list"]
[3]: ["expr", "/;",          "*",   "stmt"]
[4]: ["IDENT",               "*",   "expr_ident"]
[5]: ["expr_ident",          "*",   "expr"]
```

**State 0** (closure of `[0, 0, EOF]`):
- `[0, 0, EOF]` — start rule, expecting stmt_list
- Closure of `stmt_list` adds:
  - `[1, 0, *]` — stmt_list → • stmt_list stmt  (lookahead starts: token in FIRST(stmt_list)+EOF = {IDENT, /var, /if...} but since it has *, we simplify to * )
  - `[2, 0, *]` — stmt_list → • stmt
- Closure of `stmt` adds:
  - `[3, 0, *]` — stmt → • expr /;
- Closure of `expr` adds:
  - `[5, 0, *]` — expr → • expr_ident
- Closure of `expr_ident` adds:
  - `[4, 0, *]` — expr_ident → • IDENT

Actions for State 0:
- On `IDENT`: shift to state `goto(State0, IDENT)`

**State 1** (goto(State0, IDENT)):
- `[4, 1, *]` — expr_ident → IDENT •
- Action: reduce by rule 4 (expr_ident → IDENT)

**State 2** (goto(State1, expr_ident) — after reducing rule 4):
- Actually: after reducing, the goto from the state that pushed IDENT uses the non-terminal expr_ident
- `[5, 1, *]` — expr → expr_ident •
- Action: reduce by rule 5 (expr → expr_ident)

**State 3** (goto(State2, expr)):
- `[3, 1, *]` — stmt → expr • /;
- On `/;`: shift to State4

**State 4** (goto(State3, SLASH_SEMI)):
- `[3, 2, *]` — stmt → expr /; •
- Action: reduce by rule 3 (stmt → expr /;)

And so on. The actual DFA will have ~50-100 states.

### 3.9 Handling the SHIFT Pseudo-Rule in DFA Generation

The `SHIFT` pseudo-rule is currently used to force a shift when a reduce would also be possible. In the DFA, this translates to:

1. When a SHIFT rule's item has the dot at a position where the suffix has been fully matched, AND the lookahead matches → this is NOT a reduce, but rather signals "don't reduce here, shift instead"
2. In DFA terms: SHIFT rules contribute to the goto table but should NOT generate reduce actions
3. Implementation: Skip SHIFT rules when building reduce actions

---

## 4. Caching Strategy

### 4.1 Cache File Format and Location

**File path**: `user://cache/parser_md.dfa.tres`

- `user://` is used because `res://` is read-only in exported builds
- The `cache/` directory is created if it doesn't exist
- The `.tres` extension makes it a Godot Resource for easy `load()`/`save()`

**Cache file structure** (using Godot `Resource`):

```gdscript
# res://scenes/dfa_data.gd
extends Resource
class_name DFAData

@export var rules_hash: int = 0
@export var states: Array[Dictionary] = []
@export var token_ids: Dictionary = {}
@export var slash_token_ids: Dictionary = {}
@export var goto_table: Array[Dictionary] = []     # [{token_id: next_state}]
@export var action_table: Array[Dictionary] = []   # [{token_id: action_dict}]
# action_dict: {type: String, next_state: int, rule_idx: int, rule_len: int, rule_result: String}
```

### 4.2 Hash Computation

```gdscript
static func compute_rules_hash(rules: Array) -> int:
    var s: String = ""
    for rule in rules:
        for elem in rule:
            s += str(elem) + "|"
        s += "\n"
    return hash(s)
```

GDScript's built-in `hash()` function returns a 64-bit int — sufficient for cache invalidation. The chance of collision is negligible for this use case.

**Alternative**: Use `HashingContext` with SHA-256 for stronger guarantees, but `hash()` is simpler and fast enough.

### 4.3 Cache Invalidation Logic

```
function ensure_dfa() -> DFAData:
    var cache_path = "user://cache/parser_md.dfa.tres"
    var current_hash = compute_rules_hash(lang.rules)
    
    if FileAccess.file_exists(cache_path):
        var cached = load(cache_path) as DFAData
        if cached and cached.rules_hash == current_hash:
            return cached  # Cache hit! DFA is up-to-date
    
    # Cache miss or invalid — regenerate
    var generator = DFAGenerator.new()
    var dfa = generator.generate(lang.rules)
    dfa.rules_hash = current_hash
    
    # Save to cache
    var dir = DirAccess.open("user://")
    if not dir.dir_exists("cache"):
        dir.make_dir("cache")
    ResourceSaver.save(dfa, cache_path)
    
    return dfa
```

### 4.4 Startup Flow

```
App Launch / First Compilation
         │
         ▼
  Compute rules_hash from lang.rules
         │
         ▼
  Does cache file exist? ──No──▶ Regenerate DFA
         │                              │
        Yes                              │
         │                              │
  Load cached DFAData                    │
         │                              │
  Compare rules_hash ──Mismatch──▶ Regenerate DFA
         │                              │
        Match                            │
         │                              ▼
  ┌──────────────┐             Save to cache
  │  Use cached   │                    │
  │  DFA for all  │◀────────────────────┘
  │  parses       │
  └──────────────┘
```

**When to generate**: At first compilation request, not at app launch. This avoids startup delay and allows the app to launch quickly even if the user never compiles MiniDerp code.

**When to regenerate**: Only when `lang.rules` changes (during development). In production, the cache is generated once and reused forever.

---

## 5. DFA Parser Implementation

### 5.1 The Simplified Parse Loop

```gdscript
func parse_with_dfa(input: Dictionary, dfa: DFAData) -> AST:
    reset()
    var in_tokens: Array[Token] = input.tokens
    erep.proxy = self
    
    # Convert tokens to AST nodes
    var tokens: Array[AST] = []
    for tok in in_tokens:
        tokens.push_back(AST.new(tok))
    tokens.append(AST.new({"tok_class": "EOF", "text": ""}))
    
    # State stack parallel to AST stack
    var stack: Array[AST] = []
    var state_stack: Array[int] = [dfa.start_state]  # Start in state 0
    
    var tok_idx = 0
    while tok_idx < len(tokens):
        var tok = tokens[tok_idx]
        var current_state = state_stack[-1]
        var token_id = get_token_id(tok, dfa)
        
        # Look up action
        var action = get_action(dfa, current_state, token_id)
        
        match action.type:
            "shift":
                stack.push_back(tok)
                state_stack.push_back(action.next_state)
                tok_idx += 1
                
            "reduce":
                var rule_len = action.rule_len
                var children: Array[AST] = []
                for i in range(rule_len):
                    children.append(stack.pop_back())
                    state_stack.pop_back()
                children.reverse()
                
                var new_node = AST.new({"tok_class": action.rule_result, "text": ""})
                new_node.children = children
                stack.push_back(new_node)
                
                # Goto after reduce
                var prev_state = state_stack[-1]
                var goto_state = get_goto(dfa, prev_state, action.rule_result)
                state_stack.push_back(goto_state)
                
            "accept":
                # Successful parse
                var result = stack[0] if len(stack) > 0 else null
                if result and result.tok_class == "start":
                    linearize_ast_batch(stack)
                    sig_parse_ready.emit(stack)
                    return result
                else:
                    # Fall through to error
                    break
                    
            "error":
                push_error("syntax error")
                erep.context = tok as Token
                erep.error("syntax error")
                return false
    
    # Error handling (same as current)
    if len(stack) == 1 and stack[0].tok_class == "start":
        return stack[0]
    else:
        handle_parse_error(stack)
        return false
```

### 5.2 Token ID Lookup

```gdscript
func get_token_id(tok: AST, dfa: DFAData) -> int:
    # Check /-prefixed tokens first (matched by text)
    if tok.text in dfa.slash_token_ids:
        return dfa.slash_token_ids[tok.text]
    # Otherwise use tok_class
    if tok.tok_class in dfa.token_ids:
        return dfa.token_ids[tok.tok_class]
    # Unknown token type
    return -1  # Will trigger "error" action
```

### 5.3 Action and Goto Lookup

```gdscript
func get_action(dfa: DFAData, state: int, token_id: int) -> Dictionary:
    if state < len(dfa.action_table):
        var state_actions = dfa.action_table[state]
        if token_id in state_actions:
            return state_actions[token_id]
        # Fall back to default action (handles * wildcard)
        if -1 in state_actions:  # -1 = wildcard
            return state_actions[-1]
    return {"type": "error"}

func get_goto(dfa: DFAData, state: int, non_terminal: String) -> int:
    var nterm_id = dfa.token_ids.get(non_terminal, -1)
    if state < len(dfa.goto_table) and nterm_id in dfa.goto_table[state]:
        return dfa.goto_table[state][nterm_id]
    return 0  # Default to start state on error
```

### 5.4 State Stack Management

The state stack mirrors the AST stack exactly:
- On **shift**: push 1 token, push 1 state
- On **reduce**: pop N tokens, pop N states, then push 1 new non-terminal and push 1 goto state
- The top of the state stack always reflects the current parser state

### 5.5 Integration with Existing AST Construction

AST nodes are constructed identically to the current parser:
- [`apply_rule()`](scenes/parser_md.gd:118): pop N, reverse, create AST with `tok_class = rule[-1]`, assign children
- [`linearize_ast()`](scenes/parser_md.gd:129) / [`gather_instances()`](scenes/parser_md.gd:143): called after parsing completes (same as current)

### 5.6 Error Handling

When the DFA encounters an action `"error"`:
1. Set `error_code` (same as current)
2. Use the same error reporting path: `erep.error("syntax error")`
3. Return `false`

---

## 6. Integration Plan

### 6.1 New Files to Create

| File | Purpose |
|------|---------|
| [`scenes/dfa_data.gd`](scenes/dfa_data.gd) | `DFAData` resource class for serialization |
| [`scenes/dfa_generator_md.gd`](scenes/dfa_generator_md.gd) | DFA generation from grammar rules |
| [`scenes/dfa_parser_md.gd`](scenes/dfa_parser_md.gd) | DFA-based parser (optional, could be integrated into parser_md.gd) |

### 6.2 Changes to Existing Files

| File | Changes |
|------|---------|
| [`scenes/parser_md.gd`](scenes/parser_md.gd) | Add DFA integration: `ensure_dfa()`, modify `parse()` to dispatch to DFA or fallback |
| [`scenes/lang_md.gd`](scenes/lang_md.gd) | Add `static func get_rules_hash() -> int` or export hash function |
| [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd) | May need to pass DFA reference or let parser manage it |

### 6.3 Startup Flow

**On first compilation request** (in `comp_compile_md.compile()`):

```
1. tokenizer.tokenize(input)     [unchanged]
2. parser.ensure_dfa()            [NEW] — generates or loads DFA
3. parser.parse(input)            [modified] — uses DFA if available
4. analyzer.analyze(input)        [unchanged]
5. codegen.parse_file(input)      [unchanged]
```

The DFA generation/loading happens lazily on first parse, not at app startup. This avoids any delay for users who never compile MiniDerp code.

### 6.4 Graceful Fallback

```gdscript
# In parser_md.gd

var dfa: DFAData = null

func ensure_dfa():
    if dfa != null:
        return  # Already loaded
    dfa = DFAGenerator.get_or_generate()
    if dfa == null:
        cprint("WARNING: DFA generation failed, falling back to original parser")
        # dfa stays null, original parse() is used

func parse(input: Dictionary):
    ensure_dfa()
    if dfa != null:
        return parse_with_dfa(input, dfa)
    else:
        return parse_original(input)  # Current implementation
```

The original `parse()` function is renamed to `parse_original()` or kept as the fallback. The new `parse()` dispatches to DFA or original based on availability.

### 6.5 DFA Generation Threading

GDScript threading is limited. For DFA generation:
- **Synchronous generation**: The DFA is generated on first call to `parse()`. For a 105-rule grammar, generation should take <100ms, so this is acceptable.
- **Progress reporting**: The generator can emit signals or print progress for debugging.
- **Timeout**: If generation takes >5 seconds (which would indicate a bug), abort and fallback.

---

## 7. File-by-File Change Specification

### 7.1 NEW: [`scenes/dfa_data.gd`](scenes/dfa_data.gd)

```
extends Resource
class_name DFAData

Properties:
- @export var rules_hash: int
- @export var states: Array[Dictionary]   # [{goto: {...}, actions: {...}, default_action: {...}}]
- @export var token_ids: Dictionary       # {"IDENT": 1, "NUMBER": 2, ...}
- @export var slash_token_ids: Dictionary # {";": 32, "var": 33, ...}
```

### 7.2 NEW: [`scenes/dfa_generator_md.gd`](scenes/dfa_generator_md.gd)

```
extends Node

Static/Class Methods:
- static func get_or_generate() -> DFAData    # Main entry point
- static func compute_rules_hash(rules: Array) -> int
- static func generate(rules: Array) -> DFAData  # Core generation
- static func compute_first_sets(rules: Array) -> Dictionary
- static func compute_closure(items: Array, rules: Array, first_sets: Dictionary, token_ids: Dictionary) -> Array
- static func compute_goto(items: Array, symbol: int, rules: Array, first_sets: Dictionary, token_ids: Dictionary) -> Array
- static func state_exists(states: Array, target: Array) -> int
- static func build_action_table(states: Array, rules: Array, goto_table: Array, token_ids: Dictionary) -> Array
- static func build_token_mapping(rules: Array) -> [Dictionary, Dictionary]
```

**Approximate size**: 300-400 lines

### 7.3 NEW (optional): [`scenes/dfa_parser_md.gd`](scenes/dfa_parser_md.gd)

A standalone parser class or mixin that implements the DFA-based parse loop. This could also be integrated directly into `parser_md.gd` to reduce the number of new files.

**If separate**:
```
extends Node

Methods:
- func parse(input: Dictionary, dfa: DFAData) -> AST
- func get_token_id(tok: AST, dfa: DFAData) -> int
- func get_action(dfa: DFAData, state: int, token_id: int) -> Dictionary
- func get_goto(dfa: DFAData, state: int, non_terminal: String) -> int
```

**Approximate size**: 150-200 lines

**Recommendation**: Integrate into `parser_md.gd` to keep the codebase simpler. The DFA parser logic replaces core of the old parse loop but shares everything else (`apply_rule`, `linearize_ast`, error handling, signals).

### 7.4 MODIFIED: [`scenes/parser_md.gd`](scenes/parser_md.gd)

**Changes:**

1. Add new member variables:
   ```gdscript
   var dfa: DFAData = null
   var dfa_available: bool = false
   ```

2. Add new helper methods:
   ```gdscript
   func ensure_dfa() -> void
   func parse_with_dfa(input: Dictionary, dfa: DFAData) -> AST
   func get_token_id(tok: AST, dfa: DFAData) -> int
   func get_action(dfa: DFAData, state: int, token_id: int) -> Action
   func get_goto(dfa: DFAData, state: int, non_terminal: String) -> int
   ```

3. Modify `parse()`:
   ```gdscript
   func parse(input: Dictionary) -> AST:
       ensure_dfa()
       if dfa != null:
           return parse_with_dfa(input, dfa)
       else:
           return parse_original(input)
   ```

4. Rename old `parse()` to `parse_original()` — keep it as-is for fallback

5. Add hash computation:
   ```gdscript
   static func compute_rules_hash() -> int:
       var s = ""
       for rule in lang.rules:
           for elem in rule:
               s += str(elem) + "|"
           s += "\n"
       return hash(s)
   ```

**No changes needed to**: `apply_rule()`, `linearize_ast()`, `gather_instances()`, `rule_matches()`, `token_match()`, error handling functions, signals.

### 7.5 MODIFIED: [`scenes/lang_md.gd`](scenes/lang_md.gd)

Add helper methods:
```gdscript
static func get_rules_hash() -> int:
    var s = ""
    for rule in rules:
        for elem in rule:
            s += str(elem) + "|"
        s += "\n"
    return hash(s)
```

### 7.6 MODIFIED: [`scenes/comp_compile_md.gd`](scenes/comp_compile_md.gd)

Minimal changes — the DFA is managed internally by `parser_md`. The compile pipeline is unchanged since `parser.parse(input)` signature is preserved.

Optionally: Add a `clear_dfa_cache()` or `rebuild_dfa()` method for debugging.

---

## 8. Risks and Considerations

### 8.1 Shift/Reduce Conflicts in the Current Grammar

The grammar uses `"SHIFT"` pseudo-rules to manage precedence explicitly. These create implicit shift/reduce conflicts in the conventional LR(1) construction. The DFA generator must correctly handle SHIFT rules.

**Identified SHIFT rules** (from `lang_md.gd`):

| Line | Rule | Purpose |
|------|------|---------|
| 59 | `[expr_call, "/{", "SHIFT"]` | Don't reduce expr_call before seeing block |
| 63 | `["/func", "expr_call", "block", "*", "func_def_stmt"]` | Wait for full func definition |
| 69 | `["/if", "/(", "expr", "/)", "*", "SHIFT"]` | Don't reduce if without block |
| 71 | `["if_block", "/elif", "/(", "expr", "/)", "*", "SHIFT"]` | Chain elif |
| 73 | `["if_block", "/else", "block", "*", "if_else_block"]` | Complete if-else |
| 74-76 | Various `if_block` + lookahead SHIFT rules | Disambiguate if/elif/else |
| 109 | `["expr", "OP", "expr", "/[", "SHIFT"]` | Infix before array subscript |
| 110 | `["expr", "OP", "expr", "/(", "SHIFT"]` | Infix before function call |
| 115 | `["expr", "/,", "expr", "/[", "SHIFT"]` | Comma-separated expr before subscript |
| 116 | `["expr", "/,", "expr", "OP", "SHIFT"]` | Comma-separated expr before operator |

These translate to: when a reduce and shift are both possible, choose shift. The DFA builder must detect this and set the action to "shift" (overriding any reduce action).

**Conflict resolution strategy**: Shift overrides reduce. This matches the current parser's behavior where SHIFT rules are checked first and `break` prevents reduction.

### 8.2 Memory Overhead

Estimated DFA size:

| Component | Estimated Size |
|-----------|---------------|
| Number of states | 50-100 |
| Token type IDs | ~40-50 |
| Goto entries | ~50-100 states × ~5-10 reachable transitions = 250-1000 entries |
| Action entries | ~50-100 states × ~10-20 actions = 500-2000 entries |

In GDScript Dictionary format: ~10-50 KB (negligible for a desktop app).
In `PackedInt32Array` format: ~2-10 KB.

### 8.3 Expected Speedup

| Metric | Current Parser | DFA Parser | Improvement |
|--------|---------------|------------|-------------|
| Per-token complexity | O(R × S) — up to 105 rules × 6 stack comparisons | O(1) — two dictionary lookups | ~100-1000× |
| Cascading reductions | Restarts rule scan from beginning | Direct goto to next state | ~10-100× |
| No-stabilized-loop overhead | Yes | No (inherent in state machine) | Eliminated entirely |
| **Total compilation time** | ~50-200ms for 500 tokens | ~1-5ms for 500 tokens | **~50× speedup** |

The DFA parser eliminates three overheads:
1. No rule iteration per token (105 checks → 2 table lookups)
2. No `stabilized` loop (reductions are automatic state transitions)
3. No stack slicing / `rule_matches()` call overhead

### 8.4 Thread Safety

DFA generation is a one-time operation on the main thread. No thread safety concerns.

### 8.5 Testing Strategy

1. **Unit test**: Generate DFA from rules, verify the DFA parses simple snippets correctly
2. **Regression test**: Parse ALL existing test files (in `res/data/`) with both the old and new parser
3. **AST comparison**: For each test file, run both parsers and compare:
   - AST structure (recursively compare children and tok_class)
   - Success/failure status
   - Error messages
4. **Performance test**: Time both parsers on large inputs

```gdscript
# Pseudo-code for regression test
func test_regression():
    var test_files = ["res/data/hello.md", "res/data/miniderp.txt", ...]
    for filepath in test_files:
        var input = load_test_file(filepath)
        var result_old = parser.parse_original(input)
        var result_new = parser.parse_with_dfa(input, dfa)
        assert(asts_equal(result_old, result_new), 
               "Mismatch for " + filepath)
```

### 8.6 Maintenance

When grammar rules change (developer edits `lang_md.gd`):
1. The rules hash changes automatically
2. Cache invalidation detects the mismatch on next compilation
3. DFA is regenerated transparently
4. Developer doesn't need to manually clear cache or rebuild

**Edge case**: If the grammar changes but produces the exact same hash (extremely unlikely for 105 rules), the cache wouldn't be invalidated. Mitigation: Use `hash()` on the stringified rules, which changes if ANY element changes.

### 8.7 Limitations

- The DFA generator must correctly handle the `"*"` wildcard lookahead. In strict LR(1), each item has a specific lookahead token. The `"*"` is sugar for "any token not explicitly handled." This means the DFA's action table must have a fallback/default action per state.
- The SHIFT pseudo-rules require special handling in the DFA since they are not standard LR(1) rules.
- Grammar errors (like unreachable rules) will be exposed by the DFA generator, which is actually a benefit — it provides better diagnostics.

---

## 9. Implementation Order

1. **Create [`dfa_data.gd`](scenes/dfa_data.gd)** — Resource class for serialization
2. **Create [`dfa_generator_md.gd`](scenes/dfa_generator_md.gd)** — DFA generation algorithm
3. **Test DFA generation** — Generate DFA from current rules, print states for manual inspection
4. **Implement DFA-based parse** — Add `parse_with_dfa()` to `parser_md.gd`
5. **Add caching** — Save/load DFA to `user://cache/`
6. **Integration** — Modify `parse()` to dispatch to DFA or fallback
7. **Regression test** — Compare outputs of both parsers on all test files
8. **Performance measurement** — Before/after timing comparison
9. **Final cleanup** — Remove debug prints, add conflict detection logging

---

## 10. Appendix: Key Token Type Mappings

### 10.1 Terminal Token Classes (from tokenizer)

| tok_class | Source |
|-----------|--------|
| `IDENT` | Reclassified from WORD |
| `NUMBER` | From tokenizer |
| `STRING` | From tokenizer |
| `CHAR` | From tokenizer |
| `OP` | Reclassified from WORD or PUNCT |
| `KEYWORD` | Reclassified from WORD |
| `TYPE` | Reclassified from WORD |
| `PREPROC` | Reclassified from PUNCT (# prefix) |
| `EOF` | Synthetic end-of-input |
| `WORD` | Filtered out by reclassification |
| `PUNCT` | Mostly reclassified to OP |

### 10.2 Non-Terminal Types (from rule results)

Generated from all unique `rule[-1]` values (the result/production name):
`start`, `stmt_list`, `stmt`, `block`, `var_decl_stmt`, `assignment_stmt`, `comp_assignment_stmt`, `decl_assignment_stmt`, `decl_extern_stmt`, `func_decl_stmt`, `func_def_stmt`, `while_stmt`, `while_start`, `if_stmt`, `if_block`, `if_else_block`, `flow_stmt`, `preproc_stmt`, `expr`, `expr_immediate`, `expr_ident`, `expr_postfix`, `expr_infix`, `expr_call`, `expr_parenthesis`, `expr_array_literal`, `expr_list`, `expr_index`, `comp_asn_op`, `SHIFT` (pseudo, handled specially)

### 10.3 Virtual Token Types from `/`-prefixed Rule Elements

These are the text values from `/`-prefixed rule entries, mapped to integer IDs:
`{`, `}`, `;`, `var`, `=`, `+=`, `-=`, `*=`, `/=`, `%=`, `extern`, `func`, `while`, `(`, `)`, `if`, `elif`, `else`, `break`, `continue`, `return`, `#include` (becomes `include`), `[`, `]`, `,`
