# Baklavalang

A spatial dataflow programming language. Programs are built from **grids** — concurrent computing units placed in a 2D coordinate system that communicate through their sides.

Compiles to BEAM bytecode via Elixir.

## Quick Start

```sh
mix escript.build
./baklava examples/hello.loz
```

## Example

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

See [GUIDE.md](GUIDE.md) for the full language reference.
