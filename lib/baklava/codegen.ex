defmodule Baklava.Codegen do
  @moduledoc """
  Compiles baklava AST into dynamically defined Elixir modules.
  Each grid becomes a module with a run/2 function.
  """

  alias Baklava.AST

  @opposite %{
    right: :left,
    left: :right,
    up: :down,
    down: :up
  }

  @doc """
  Compile all grids into modules. Returns a map of grid_name => module_name.
  """
  def compile_all(grid_defs) do
    Map.new(grid_defs, fn {name, grid} ->
      mod = compile_grid(name, grid)
      {name, mod}
    end)
  end

  defp compile_grid(name, %AST.Grid{body: %AST.Block{stmts: stmts}}) do
    {init_stmts, receive_clauses} = split_init_and_receives(stmts)
    mod_name = Module.concat(Baklava.Grids, String.capitalize(name))

    init_code = Enum.map(init_stmts, &compile_stmt/1)
    input_count = length(receive_clauses)

    run_body =
      if receive_clauses == [] do
        # Pure generator/init-only grid
        quote do
          def run(channels, parent) do
            _ = parent
            unquote_splicing(init_code)
          end
        end
      else
        data_clauses = compile_receive_clauses(receive_clauses)

        eof_clause =
          quote do
            :eof ->
              if eof_remaining - 1 <= 0 do
                :ok
              else
                receive_loop(channels, parent, eof_remaining - 1)
              end
          end

        halt_clause =
          quote do
            :halt -> :ok
          end

        all_clauses = data_clauses ++ eof_clause ++ halt_clause

        quote do
          def run(channels, parent) do
            unquote_splicing(init_code)
            receive_loop(channels, parent, unquote(input_count))
          end

          defp receive_loop(channels, parent, eof_remaining) do
            receive do
              unquote(all_clauses)
            end
          end
        end
      end

    # Purge existing module if re-compiling
    :code.purge(mod_name)
    :code.delete(mod_name)

    Module.create(mod_name, run_body, Macro.Env.location(__ENV__))
    mod_name
  end

  defp split_init_and_receives(stmts) do
    Enum.split_with(stmts, fn
      %AST.Receive{} -> false
      _ -> true
    end)
  end

  defp compile_receive_clauses(clauses) do
    Enum.flat_map(clauses, fn %AST.Receive{direction: dir, pattern: pattern, body: body} ->
      pattern_ast = compile_pattern(pattern)
      body_code = compile_body(body)

      quote do
        {:data, unquote(dir), unquote(pattern_ast)} ->
          unquote(body_code)
          receive_loop(channels, parent, eof_remaining)
      end
    end)
  end

  defp compile_pattern(%AST.Var{name: name}) do
    Macro.var(String.to_atom(name), nil)
  end

  defp compile_pattern(%AST.Lit{value: v}), do: Macro.escape(v)

  defp compile_pattern(%AST.Wildcard{}) do
    Macro.var(:_, nil)
  end

  defp compile_pattern(%AST.Tuple{elements: elements}) do
    {:{}, [], Enum.map(elements, &compile_pattern/1)}
  end

  defp compile_pattern(%AST.List{elements: [], tail: nil}) do
    []
  end

  defp compile_pattern(%AST.List{elements: elements, tail: nil}) do
    Enum.map(elements, &compile_pattern/1)
  end

  defp compile_pattern(%AST.List{elements: [head], tail: tail}) do
    [{:|, [], [compile_pattern(head), compile_pattern(tail)]}]
  end

  defp compile_body(%AST.Block{stmts: stmts}) do
    compiled = Enum.map(stmts, &compile_stmt/1)
    {:__block__, [], compiled}
  end

  defp compile_body(stmt), do: compile_stmt(stmt)

  # Statements
  defp compile_stmt(%AST.Emit{direction: dir, expr: expr}) do
    opposite = @opposite[dir]
    expr_code = compile_expr(expr)

    quote do
      send(Map.fetch!(channels, {:out, unquote(dir)}), {:data, unquote(opposite), unquote(expr_code)})
    end
  end

  defp compile_stmt(%AST.Halt{}) do
    quote do
      send(parent, :halt)
      exit(:normal)
    end
  end

  defp compile_stmt(%AST.If{cond: cond_expr, then: then_body, else: else_body}) do
    cond_code = compile_expr(cond_expr)
    then_code = compile_body(then_body)

    if else_body do
      else_code = compile_body(else_body)
      quote do
        if unquote(cond_code), do: unquote(then_code), else: unquote(else_code)
      end
    else
      quote do
        if unquote(cond_code), do: unquote(then_code)
      end
    end
  end

  defp compile_stmt(%AST.Call{} = call), do: compile_expr(call)
  defp compile_stmt(%AST.BinOp{} = expr), do: compile_expr(expr)
  defp compile_stmt(%AST.Lit{}), do: quote(do: :ok)
  defp compile_stmt(%AST.Var{}), do: quote(do: :ok)

  # Expressions
  defp compile_expr(%AST.Lit{value: v}) when is_binary(v), do: v
  defp compile_expr(%AST.Lit{value: v}), do: v

  defp compile_expr(%AST.Var{name: name}) do
    Macro.var(String.to_atom(name), nil)
  end

  defp compile_expr(%AST.Tuple{elements: elements}) do
    {:{}, [], Enum.map(elements, &compile_expr/1)}
  end

  defp compile_expr(%AST.List{elements: [], tail: nil}), do: []

  defp compile_expr(%AST.List{elements: elements, tail: nil}) do
    Enum.map(elements, &compile_expr/1)
  end

  defp compile_expr(%AST.List{elements: [head], tail: tail}) do
    [{:|, [], [compile_expr(head), compile_expr(tail)]}]
  end

  defp compile_expr(%AST.BinOp{op: op, left: left, right: right}) do
    l = compile_expr(left)
    r = compile_expr(right)

    case op do
      :+ -> quote(do: unquote(l) + unquote(r))
      :- -> quote(do: unquote(l) - unquote(r))
      :* -> quote(do: unquote(l) * unquote(r))
      :/ -> quote(do: div(unquote(l), unquote(r)))
      :== -> quote(do: unquote(l) == unquote(r))
      :!= -> quote(do: unquote(l) != unquote(r))
      :< -> quote(do: unquote(l) < unquote(r))
      :> -> quote(do: unquote(l) > unquote(r))
      :<= -> quote(do: unquote(l) <= unquote(r))
      :>= -> quote(do: unquote(l) >= unquote(r))
    end
  end

  defp compile_expr(%AST.Call{module: nil, name: name, args: args}) do
    func = String.to_atom(name)
    arg_codes = Enum.map(args, &compile_expr/1)
    {func, [], arg_codes}
  end

  defp compile_expr(%AST.Call{module: mod, name: name, args: args}) do
    mod_atom = String.to_atom("Elixir.#{mod}")
    func_atom = String.to_atom(name)
    arg_codes = Enum.map(args, &compile_expr/1)
    {{:., [], [mod_atom, func_atom]}, [], arg_codes}
  end
end
