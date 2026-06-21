## MiniDerp Language — All 22 Implemented Syntax Constructs

Below is every syntax construct currently implemented. All are compiled through the full pipeline (tokenize → parse → analyze → codegen → assembly) unless noted.

---

### 1. Declarations

**Variable Declaration** — `var name;`
```c
var x;
var scr_I;
```
Declares a variable with no initial value.

**Declaration + Assignment** — `var name = expr;`
```c
var x = 0;
var hex = "0123456789ABCDEF";
```
Declares and initializes in one statement.

**Extern Declaration** — `extern var name;` / `extern func name(args);`
```c
extern var y;
extern func putch(c);
```
Alerts the compiler that a symbol is defined externally.

**Function Declaration (forward)** — `func name(args);`
```c
func main();
func print(str, r, g, b);
func alloc(size);
```
Forward-declares a function — its definition may appear later.

**Function Definition** — `func name(args) { ... }`
```c
func main(){
    print("Hello World!", 128,255,0);
}
func infloop(){ while(1){} }
```
Defines a function with optional comma-separated parameters and a body block. Supports return values.

---

### 2. Assignment

**Assignment** — `lvalue = expr;`
```c
x = 2;
adr_scr[scr_I] = b;
args[0] = "world";
```
Assigns to a variable or array element. LHS can be an identifier or `a[i]`.

---

### 3. Control Flow

**While Loop** — `while(condition) { ... }`
```c
while(c){
    putch(c, r,g,b);
    i++;
    c = str[i*4];
}
```
Classic loop. Condition evaluated before each iteration. Supports `break`/`continue`.

**If / Elif / Else**
```c
if(1){
    x = 2;
}elif(3){
    x = 4;
}else{
    x = 5;
}
```
Full conditional chain: one `if`, any number of `elif`, optional final `else`.

**Break** — `break;`
```c
while(1){
    if(foo) break;
}
```
Exits the innermost while loop.

**Continue** — `continue;`
```c
while(i < 10){
    i++;
    if(i > 5) continue;
}
```
Jumps to the next iteration's condition check.

**Return (no value)** — `return;`
```c
func done(){ return; }
```

**Return (with value)** — `return expr;`
```c
func alloc(size){
    var res = alloc_p;
    alloc_p = alloc_p + size;
    return res;
}
```

---

### 4. Preprocessor

**Include Directive** — `#include "filename"`
```c
#include "asm_screen.txt"
```
✅ Parsed into AST, but the analyzer body is a **no-op** (inclusion is not yet semantically processed).

---

### 5. Blocks

**Curly-Brace Block** — `{ ... }`
```c
{
    var c = str[i];
    putch(c, r,g,b);
}
```
Groups zero or more statements. Used inside functions, loops, and if/elif/else bodies. Empty block `{}` is also valid.

---

### 6. Expressions

**Numeric Literal**
```c
128, 255, 0, 67536
```
Integer or float.

**String Literal**
```c
"Hello World!"
"0123456789ABCDEF"
```
Double-quoted string.

**Character Literal**
```c
'a'
'\n'
```

**Identifier Reference**
```c
x, str, main, putch
```
Resolves variable or function names.

**Infix Operators**
```c
c = str[i*4];
num = num / 10;
x == y
x < y
```
Binary operations. Supported operators and their IR mappings:

| Token | IR Op | Token | IR Op |
|-------|-------|-------|-------|
| `+` | ADD | `<` | LESS |
| `-` | SUB | `==` | EQUAL |
| `*` | MUL | `!=` | NOT_EQUAL |
| `/` | DIV | `&&` / `and` | AND |
| `%` | MOD | `\|\|` / `or` | OR |
| `>` | GREATER | `!` / `not` | NOT |
| `&` | B_AND | `>>` | B_SHIFT_RIGHT |
| `\|` | B_OR | `<<` | B_SHIFT_LEFT |
| `^` | B_XOR | `~` | B_NOT |

⚠️ Note: `.`, `+=`, `-=`, `*=`, `/=`, `%=` are tokenized but have **no semantic mapping** — using them triggers an error.

**Array Indexing** — `expr[expr]`
```c
c = str[i*4];
adr_scr[scr_I] = b;
args[0] = "world";
```
Maps to the `INDEX` IR opcode (address = base + offset).

**Postfix ++ / --**
```c
i++;
x--;
```
Unary increment/decrement. Recognized before `;`, `)`, and `]`.

**Function Call** — `name(arg1, arg2, ...)`
```c
main();
print("Hello World!", 128,255,0);
strlen("\n");
has_char();
```
Zero or more comma-separated arguments. Returns a value usable in further expressions.

**Parenthesized Expression** — `(expr)`
```c
c = str[i*4];  /* the i*4 is parenthesized implicitly */
```
Standard precedence grouping.

---

### Summary

| # | Construct | File Example | Status |
|---|-----------|-------------|--------|
| 1 | Variable declaration | `hello.md:6` | ✅ Full |
| 2 | Declaration + assignment | `return_test.md:2` | ✅ Full |
| 3 | Extern declaration | `miniderp.txt:7-8` | ✅ Full |
| 4 | Forward function declaration | `hello.md:1-5` | ⚠️ Buggy (crashes `fixup_cb_lbls`) |
| 5 | Function definition | `hello.md:13` | ✅ Full |
| 6 | Assignment | `array_test.md:7` | ✅ Full |
| 7 | While loop | `hello.md:19` | ✅ Full |
| 8 | If / elif / else | `elif_test.md:2-8` | ✅ Full |
| 9 | Break | — | ✅ Full |
| 10 | Continue | — | ✅ Full |
| 11 | Return (void) | — | ✅ Full |
| 12 | Return (value) | `return_test.md:4` | ✅ Full |
| 13 | #include | `miniderp.txt:5` | ⚠️ Parsed only, analyzer no-op |
| 14 | Block `{ ... }` | `hello.md:13` | ✅ Full |
| 15 | Numeric literal | all files | ✅ Full |
| 16 | String literal | `hello.md:14` | ✅ Full |
| 17 | Identifier | all files | ✅ Full |
| 18 | Infix operator | `array_test.md:7` | ✅ Full |
| 19 | Array indexing `a[i]` | `hello.md:20` | ✅ Full |
| 20 | Postfix `++`/`--` | `miniderp.txt:15` | ✅ Full |
| 21 | Function call | `hello.md:9` | ✅ Full |
| 22 | Parenthesized `(expr)` | all files | ✅ Full |