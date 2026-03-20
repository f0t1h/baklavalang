# Baklavalang Guide

Baklavalang is a spatial dataflow programming language. Programs are built from **grids** — concurrent computing units placed in a 2D coordinate system that communicate through their sides.

## Core Concepts

### Grids

A grid is a rectangular computing unit defined with `name [ ... ]`:

```
myGrid [
  // grid logic here
]
```

Each grid runs as an independent concurrent process. Grids have four sides: **left**, **right**, **up**, **down**. Each side can either receive input or emit output, inferred from usage.

### Data Flow Operators

Data enters and exits grids through their sides using two symbols:
- `#` — the outside (source of incoming data)
- `$` — the outside (destination of outgoing data)

**Receiving** (data flows from `#` into a variable):

| Syntax | Meaning |
|--------|---------|
| `# \|> val` | Receive from left |
| `val <\| #` | Receive from right |
| `# \|^ val` | Receive from below |
| `val \|v #` | Receive from above |

**Emitting** (data flows from expression to `$`):

| Syntax | Meaning |
|--------|---------|
| `expr \|> $` | Emit right |
| `$ <\| expr` | Emit left |
| `expr \|^ $` | Emit up |
| `$ \|v expr` | Emit down |

### Pattern Matching

Receive clauses support pattern matching. Multiple clauses from the same direction are tried in order — first match wins:

```
myGrid [
  // match empty list
  # |> [] => halt

  // match list head/tail
  # |> [h | t] => {
    h |> $
    $ |v t
  }

  // match exact value
  # |> 0 => halt

  // match tuple
  # |> {x, y} => x + y |> $

  // match string literal
  # |> "done" => halt

  // wildcard (match anything, don't bind)
  # |> _ => halt
]
```

Supported patterns: variables, literals (integers, strings, booleans), `_` wildcard, tuples `{a, b, ...}`, lists `[]`, `[a, b]`, `[h | t]`.

## Placement

Grids are placed in a 2D coordinate system using the `main:` section. Grid names are **tab-separated** — their literal position in the text is their position in the grid:

```
main:
seed	cntr	prnt
^<--	<--v
```

This creates:
```
(0,0) seed    (1,0) cntr    (2,0) prnt
(0,1) ^<--    (1,1) <--v
```

Adjacent grids connect automatically: one grid's output side must meet the neighbor's input side. Mismatches are compile errors.

### Rules

- Each side is either input or output (inferred from code)
- No gaps between connected grids
- No fan-in or fan-out — strict 1:1 connections
- All connections use bounded SPSC (single-producer single-consumer) queues

## Built-in Relay Symbols

Relays pass data from one side to another. Instead of writing relay grids manually, use these 4-character symbols directly in the `main:` section:

| From \ To | Left | Right | Up | Down |
|-----------|------|-------|-----|------|
| **Left** | — | `-->>` | `-->^` | `-->v` |
| **Right** | `<<--` | — | `^<--` | `v<--` |
| **Top** | `<--v` | `v-->` | — | `vvvv` |
| **Bottom** | `<--^` | `^-->` | `^^^^` | — |

Example — a counter loop using relays instead of manually defined relay grids:

```
main:
cntr	-->v
^<--	<--v
```

## Execution Model

### Init and Receive Phases

A grid's body runs in two phases:

1. **Init phase**: All statements before the first receive clause run once, sequentially.
2. **Receive phase**: All receive clauses form a selective receive loop that runs until termination.

```
myGrid [
  // Init: runs once
  0 |> $

  // Receive loop: runs repeatedly
  # |^ val => val + 1 |> $
]
```

This is how loops work — the init phase seeds a value, receive clauses process and re-emit, and relay grids carry the value back around.

### Termination

`halt` terminates the entire program. When a grid executes `halt`:

1. The grid signals the parent runtime
2. The parent sends a halt message to all grid processes
3. Each grid finishes processing queued messages (FIFO), then stops
4. Program exits cleanly

```
cntr [
  # |> 0 => halt
  # |> n => {
    IO.puts(n)
    $ |v (n - 1)
  }
]
```

## Expressions

### Arithmetic and Comparison

```
a + b    a - b    a * b    a / b
a == b   a != b   a < b    a > b   a <= b   a >= b
```

### Data Structures

```
// Tuples
{1, "hello", true}

// Lists
[1, 2, 3]
[head | tail]
[]
```

### Control Flow

```
if condition {
  // then
} else {
  // else
}
```

### Elixir Interop

Grid bodies compile to BEAM bytecode. You can call any Elixir module function directly:

```
IO.puts(value)
IO.write(ch)
IO.inspect(data)
String.graphemes("hello")
String.first(str)
String.length(str)
String.upcase(str)
Enum.map(list, fun)
Enum.reverse(list)
Integer.to_string(n)
```

The entire Elixir/Erlang standard library is available.

### Comments

```
// single-line comment
```

## Iteration Without Loops

Baklavalang has no `for` or `while` loops. Iteration is achieved through **grid topology** — data circulates through a loop of grids:

```
seed [
  0 |> $
  # |^ val => val |> $
]

cntr [
  # |> val => {
    if val < 10 {
      IO.puts(val)
      val + 1 |> $
    } else {
      halt
    }
  }
]

main:
seed	cntr
^<--	<--v
```

The seed grid emits 0, relay grids carry the incremented value back to seed, which passes it to cntr again. The topology IS the loop.

## Complete Examples

### Counter (0-9)

```
cntr [
  0 |> $

  # |^ val => {
    if val < 10 {
      IO.puts(val)
      val + 1 |> $
    } else {
      halt
    }
  }
]

main:
cntr	-->v
^<--	<--v
```

### Hello World (character pipeline)

```
seed [
  String.graphemes("Hello, World!") |> $
  # |^ val => val |> $
]

cntr [
  # |> [] => halt
  # |> [h | t] => {
    h |> $
    $ |v t
  }
]

prnt [
  # |> ch => IO.write(ch)
]

main:
seed	cntr	prnt
^<--	<--v
```

## Running Programs

```sh
# Build the CLI
mix escript.build

# Run a program
./baklava examples/hello.loz

# File extension: .loz
```
