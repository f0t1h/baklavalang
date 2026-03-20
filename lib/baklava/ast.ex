defmodule Baklava.AST do
  @moduledoc """
  AST node definitions for gridlan.
  """

  # Top-level program
  defmodule Program do
    defstruct [:grids, :main]
  end

  # Grid definition: name [ body ]
  defmodule Grid do
    defstruct [:name, :body]
  end

  # Main placement: main:\n tab-separated grid layout
  defmodule Main do
    # rows is a list of lists of (name | nil)
    # e.g. [["gen", "double", "printer"], [nil, "sink", nil]]
    defstruct [:rows]
  end

  # Statements
  defmodule Emit do
    # direction: :right, :left, :up, :down
    defstruct [:direction, :expr]
  end

  defmodule Receive do
    # direction: :right, :left, :up, :down
    # pattern: Var (bind) or Lit (match exact value)
    # body: what to execute with the matched value
    defstruct [:direction, :pattern, :body]
  end

  defmodule If do
    defstruct [:cond, :then, :else]
  end

  defmodule Call do
    # module: nil for bare calls, "IO" etc for module calls
    defstruct [:module, :name, :args]
  end

  defmodule BinOp do
    defstruct [:op, :left, :right]
  end

  defmodule Var do
    defstruct [:name]
  end

  defmodule Lit do
    defstruct [:value]
  end

  defmodule Tuple do
    defstruct [:elements]
  end

  defmodule List do
    # elements: list of AST nodes
    # tail: nil for exact list, AST node for [h | t] cons pattern
    defstruct [:elements, :tail]
  end

  defmodule Wildcard do
    defstruct []
  end

  defmodule Let do
    defstruct [:name, :value]
  end

  defmodule Halt do
    defstruct []
  end

  defmodule Block do
    defstruct [:stmts]
  end
end
