defmodule Baklava.Parser do
  @moduledoc """
  Parser for gridlan. Transforms tokens into AST nodes.
  """

  alias Baklava.AST

  @spec parse([Baklava.Lexer.token()]) :: {:ok, AST.Program.t()} | {:error, String.t()}
  def parse(tokens) do
    tokens = drop_newlines(tokens)
    # relay_counter tracks auto-generated relay names
    Process.put(:relay_counter, 0)
    parse_program(tokens, [], nil)
  end

  defp parse_program([], grids, main) do
    {:ok, %AST.Program{grids: Enum.reverse(grids), main: main}}
  end

  defp parse_program(tokens, grids, main) do
    tokens = drop_newlines(tokens)

    case tokens do
      [] ->
        parse_program([], grids, main)

      [:kw_main, :colon | rest] ->
        {main_node, relay_grids, rest} = parse_main(rest)
        parse_program(rest, relay_grids ++ grids, main_node)

      [{:ident, name}, :open_bracket | rest] ->
        {body, rest} = parse_grid_body(rest, [])
        grid = %AST.Grid{name: name, body: %AST.Block{stmts: body}}
        parse_program(rest, [grid | grids], main)

      [tok | _] ->
        {:error, "unexpected token at top level: #{inspect(tok)}"}
    end
  end

  # Parse main: section - tab-separated grid names and relay symbols
  # Returns {main_node, relay_grids, rest}
  defp parse_main(tokens) do
    tokens = drop_only_newlines(tokens)
    {rows, relay_grids, rest} = parse_main_rows(tokens, [], [])
    {%AST.Main{rows: Enum.reverse(rows)}, relay_grids, rest}
  end

  defp parse_main_rows(tokens, rows, relays) do
    case tokens do
      [] ->
        {rows, relays, []}

      [{:ident, _} | _] ->
        {row, new_relays, rest} = parse_main_row(tokens, [], [])
        rest = drop_only_newlines(rest)
        parse_main_rows(rest, [Enum.reverse(row) | rows], new_relays ++ relays)

      [{:relay, _, _} | _] ->
        {row, new_relays, rest} = parse_main_row(tokens, [], [])
        rest = drop_only_newlines(rest)
        parse_main_rows(rest, [Enum.reverse(row) | rows], new_relays ++ relays)

      [:tab | rest] ->
        {row, new_relays, rest} = parse_main_row(rest, [nil], [])
        rest = drop_only_newlines(rest)
        parse_main_rows(rest, [Enum.reverse(row) | rows], new_relays ++ relays)

      _ ->
        {rows, relays, tokens}
    end
  end

  defp parse_main_row(tokens, cells, relays) do
    case tokens do
      [{:ident, name}, :tab | rest] ->
        parse_main_row(rest, [name | cells], relays)

      [{:ident, name}, :newline | rest] ->
        {[name | cells], relays, rest}

      [{:ident, name} | rest] ->
        {[name | cells], relays, rest}

      [{:relay, from, to}, :tab | rest] ->
        {name, grid} = make_relay_grid(from, to)
        parse_main_row(rest, [name | cells], [grid | relays])

      [{:relay, from, to}, :newline | rest] ->
        {name, grid} = make_relay_grid(from, to)
        {[name | cells], [grid | relays], rest}

      [{:relay, from, to} | rest] ->
        {name, grid} = make_relay_grid(from, to)
        {[name | cells], [grid | relays], rest}

      [:tab | rest] ->
        parse_main_row(rest, [nil | cells], relays)

      _ ->
        {cells, relays, tokens}
    end
  end

  defp make_relay_grid(from, to) do
    n = Process.get(:relay_counter)
    Process.put(:relay_counter, n + 1)
    name = "__relay_#{n}"

    # Map from/to to the internal direction names used by receive/emit
    recv_dir = case from do
      :left -> :left
      :right -> :right
      :top -> :up
      :bottom -> :down
    end

    emit_dir = case to do
      :left -> :left
      :right -> :right
      :up -> :up
      :down -> :down
    end

    body = %AST.Block{
      stmts: [
        %AST.Receive{
          direction: recv_dir,
          pattern: %AST.Var{name: "rv"},
          body: %AST.Emit{direction: emit_dir, expr: %AST.Var{name: "rv"}}
        }
      ]
    }

    {name, %AST.Grid{name: name, body: body}}
  end

  # Parse statements inside a grid [ ... ]
  defp parse_grid_body([:close_bracket | rest], acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_grid_body(tokens, acc) do
    tokens = drop_newlines(tokens)

    case tokens do
      [:close_bracket | rest] ->
        {Enum.reverse(acc), rest}

      [] ->
        {Enum.reverse(acc), []}

      _ ->
        {stmt, rest} = parse_stmt(tokens)
        parse_grid_body(rest, [stmt | acc])
    end
  end

  # Statements
  defp parse_stmt(tokens) do
    tokens = drop_newlines(tokens)

    case tokens do
      # Receive from left: # |> pattern => body
      [:hash, :pipe_right | rest] ->
        {pattern, rest} = parse_receive_pattern(rest)
        [:arrow | rest] = rest
        {body, rest} = parse_stmt_or_block(rest)
        {%AST.Receive{direction: :left, pattern: pattern, body: body}, rest}

      # Receive from below: # |^ pattern => body
      [:hash, :pipe_up | rest] ->
        {pattern, rest} = parse_receive_pattern(rest)
        [:arrow | rest] = rest
        {body, rest} = parse_stmt_or_block(rest)
        {%AST.Receive{direction: :down, pattern: pattern, body: body}, rest}

      # Let binding: let x = expr
      [:kw_let, {:ident, name}, :equal | rest] ->
        {value, rest} = parse_expr(rest)
        {%AST.Let{name: name, value: value}, rest}

      # Halt
      [:kw_halt | rest] ->
        {%AST.Halt{}, rest}

      # If
      [:kw_if | rest] ->
        {cond_expr, rest} = parse_expr(rest)
        [:open_brace | rest] = rest
        {then_body, rest} = parse_block_body(rest, [])
        {else_body, rest} =
          case drop_newlines(rest) do
            [:kw_else, :open_brace | rest] ->
              parse_block_body(rest, [])
            rest ->
              {nil, rest}
          end
        {%AST.If{cond: cond_expr, then: %AST.Block{stmts: then_body}, else: else_body && %AST.Block{stmts: else_body}}, rest}

      _ ->
        # Try to parse as expression-statement (emit, receive via ident, or bare expr)
        parse_expr_stmt(tokens)
    end
  end

  defp parse_stmt_or_block(tokens) do
    tokens = drop_newlines(tokens)

    case tokens do
      [:open_brace | rest] ->
        {stmts, rest} = parse_block_body(rest, [])
        {%AST.Block{stmts: stmts}, rest}

      _ ->
        parse_stmt(tokens)
    end
  end

  defp parse_block_body(tokens, acc) do
    tokens = drop_newlines(tokens)

    case tokens do
      [:close_brace | rest] ->
        {Enum.reverse(acc), rest}

      [] ->
        {Enum.reverse(acc), []}

      _ ->
        {stmt, rest} = parse_stmt(tokens)
        parse_block_body(rest, [stmt | acc])
    end
  end

  # Expression statements: things like `val * 2 |> $` or `$ <| val` or `IO.puts(val)`
  defp parse_expr_stmt(tokens) do
    case tokens do
      # Receive from right: pattern <| # => ...
      [{:ident, var}, :left_pipe, :hash, :arrow | rest] ->
        {body, rest} = parse_stmt_or_block(rest)
        {%AST.Receive{direction: :right, pattern: %AST.Var{name: var}, body: body}, rest}

      [{:int, n}, :left_pipe, :hash, :arrow | rest] ->
        {body, rest} = parse_stmt_or_block(rest)
        {%AST.Receive{direction: :right, pattern: %AST.Lit{value: n}, body: body}, rest}

      [{:string, s}, :left_pipe, :hash, :arrow | rest] ->
        {body, rest} = parse_stmt_or_block(rest)
        {%AST.Receive{direction: :right, pattern: %AST.Lit{value: s}, body: body}, rest}

      # Receive from above: pattern |v # => ...
      [{:ident, var}, :pipe_down, :hash, :arrow | rest] ->
        {body, rest} = parse_stmt_or_block(rest)
        {%AST.Receive{direction: :up, pattern: %AST.Var{name: var}, body: body}, rest}

      [{:int, n}, :pipe_down, :hash, :arrow | rest] ->
        {body, rest} = parse_stmt_or_block(rest)
        {%AST.Receive{direction: :up, pattern: %AST.Lit{value: n}, body: body}, rest}

      [{:string, s}, :pipe_down, :hash, :arrow | rest] ->
        {body, rest} = parse_stmt_or_block(rest)
        {%AST.Receive{direction: :up, pattern: %AST.Lit{value: s}, body: body}, rest}

      # Emit left: $ <| expr
      [:dollar, :left_pipe | rest] ->
        {expr, rest} = parse_expr(rest)
        {%AST.Emit{direction: :left, expr: expr}, rest}

      # Emit down: $ |v expr
      [:dollar, :pipe_down | rest] ->
        {expr, rest} = parse_expr(rest)
        {%AST.Emit{direction: :down, expr: expr}, rest}

      _ ->
        # Parse as expression, then check for trailing emit
        {expr, rest} = parse_expr(tokens)

        case rest do
          # Emit right: expr |> $
          [:pipe_right, :dollar | rest] ->
            {%AST.Emit{direction: :right, expr: expr}, rest}

          # Emit up: expr |^ $
          [:pipe_up, :dollar | rest] ->
            {%AST.Emit{direction: :up, expr: expr}, rest}

          _ ->
            # Bare expression statement (e.g. function call)
            {expr, rest}
        end
    end
  end

  # Expression parsing with precedence climbing
  defp parse_expr(tokens), do: parse_comparison(tokens)

  defp parse_comparison(tokens) do
    {left, rest} = parse_addition(tokens)
    parse_comparison_rest(left, rest)
  end

  defp parse_comparison_rest(left, tokens) do
    case tokens do
      [:equal_equal | rest] ->
        {right, rest} = parse_addition(rest)
        parse_comparison_rest(%AST.BinOp{op: :==, left: left, right: right}, rest)

      [:bang_equal | rest] ->
        {right, rest} = parse_addition(rest)
        parse_comparison_rest(%AST.BinOp{op: :!=, left: left, right: right}, rest)

      [:less | rest] ->
        {right, rest} = parse_addition(rest)
        parse_comparison_rest(%AST.BinOp{op: :<, left: left, right: right}, rest)

      [:greater | rest] ->
        {right, rest} = parse_addition(rest)
        parse_comparison_rest(%AST.BinOp{op: :>, left: left, right: right}, rest)

      [:less_equal | rest] ->
        {right, rest} = parse_addition(rest)
        parse_comparison_rest(%AST.BinOp{op: :<=, left: left, right: right}, rest)

      [:greater_equal | rest] ->
        {right, rest} = parse_addition(rest)
        parse_comparison_rest(%AST.BinOp{op: :>=, left: left, right: right}, rest)

      _ ->
        {left, tokens}
    end
  end

  defp parse_addition(tokens) do
    {left, rest} = parse_multiplication(tokens)
    parse_addition_rest(left, rest)
  end

  defp parse_addition_rest(left, tokens) do
    case tokens do
      [:plus | rest] ->
        {right, rest} = parse_multiplication(rest)
        parse_addition_rest(%AST.BinOp{op: :+, left: left, right: right}, rest)

      [:minus | rest] ->
        {right, rest} = parse_multiplication(rest)
        parse_addition_rest(%AST.BinOp{op: :-, left: left, right: right}, rest)

      _ ->
        {left, tokens}
    end
  end

  defp parse_multiplication(tokens) do
    {left, rest} = parse_primary(tokens)
    parse_multiplication_rest(left, rest)
  end

  defp parse_multiplication_rest(left, tokens) do
    case tokens do
      [:star | rest] ->
        {right, rest} = parse_primary(rest)
        parse_multiplication_rest(%AST.BinOp{op: :*, left: left, right: right}, rest)

      [:slash | rest] ->
        {right, rest} = parse_primary(rest)
        parse_multiplication_rest(%AST.BinOp{op: :/, left: left, right: right}, rest)

      _ ->
        {left, tokens}
    end
  end

  defp parse_primary(tokens) do
    tokens = drop_newlines(tokens)

    case tokens do
      [{:int, n} | rest] ->
        {%AST.Lit{value: n}, rest}

      [{:string, s} | rest] ->
        {%AST.Lit{value: s}, rest}

      [:kw_true | rest] ->
        {%AST.Lit{value: true}, rest}

      [:kw_false | rest] ->
        {%AST.Lit{value: false}, rest}

      [{:ident, mod}, :dot, {:ident, func}, :open_paren | rest] ->
        {args, rest} = parse_args(rest, [])
        {%AST.Call{module: mod, name: func, args: args}, rest}

      [{:ident, name}, :open_paren | rest] ->
        {args, rest} = parse_args(rest, [])
        {%AST.Call{module: nil, name: name, args: args}, rest}

      [{:ident, name} | rest] ->
        {%AST.Var{name: name}, rest}

      [:open_paren | rest] ->
        {expr, rest} = parse_expr(rest)
        [:close_paren | rest] = rest
        {expr, rest}

      # Tuple expression: {a, b, c}
      [:open_brace | rest] ->
        {elements, rest} = parse_expr_list(rest, :close_brace)
        {%AST.Tuple{elements: elements}, rest}

      # List expression: [] or [a, b] or [h | t]
      [:open_bracket | rest] ->
        parse_list_expr(rest)

      [tok | _] ->
        raise "unexpected token in expression: #{inspect(tok)}"
    end
  end

  defp parse_list_expr([:close_bracket | rest]) do
    {%AST.List{elements: [], tail: nil}, rest}
  end

  defp parse_list_expr(tokens) do
    {first, rest} = parse_expr(tokens)

    case rest do
      [:pipe | rest] ->
        {tail, rest} = parse_expr(rest)
        [:close_bracket | rest] = rest
        {%AST.List{elements: [first], tail: tail}, rest}

      [:comma | rest] ->
        {remaining, rest} = parse_expr_list_rest(rest, [])
        {%AST.List{elements: [first | remaining], tail: nil}, rest}

      [:close_bracket | rest] ->
        {%AST.List{elements: [first], tail: nil}, rest}
    end
  end

  defp parse_expr_list(tokens, close_token) do
    parse_expr_list(tokens, close_token, [])
  end

  defp parse_expr_list([token | rest], close_token, acc) when token == close_token do
    {Enum.reverse(acc), rest}
  end

  defp parse_expr_list(tokens, close_token, acc) do
    {expr, rest} = parse_expr(tokens)

    case rest do
      [:comma | rest] -> parse_expr_list(rest, close_token, [expr | acc])
      _ -> parse_expr_list(rest, close_token, [expr | acc])
    end
  end

  defp parse_expr_list_rest(tokens, acc) do
    {expr, rest} = parse_expr(tokens)

    case rest do
      [:comma | rest] -> parse_expr_list_rest(rest, [expr | acc])
      [:close_bracket | rest] -> {Enum.reverse([expr | acc]), rest}
    end
  end

  defp parse_receive_pattern(tokens) do
    case tokens do
      [{:ident, "_"} | rest] ->
        {%AST.Wildcard{}, rest}

      [{:ident, name} | rest] ->
        {%AST.Var{name: name}, rest}

      [{:int, n} | rest] ->
        {%AST.Lit{value: n}, rest}

      [{:string, s} | rest] ->
        {%AST.Lit{value: s}, rest}

      [:kw_true | rest] ->
        {%AST.Lit{value: true}, rest}

      [:kw_false | rest] ->
        {%AST.Lit{value: false}, rest}

      # Tuple pattern: {a, b, c}
      [:open_brace | rest] ->
        {elements, rest} = parse_pattern_list(rest, :close_brace)
        {%AST.Tuple{elements: elements}, rest}

      # List pattern: [] or [a, b] or [h | t]
      [:open_bracket | rest] ->
        parse_list_pattern(rest)

      [tok | _] ->
        raise "unexpected token in receive pattern: #{inspect(tok)}"
    end
  end

  defp parse_list_pattern([:close_bracket | rest]) do
    {%AST.List{elements: [], tail: nil}, rest}
  end

  defp parse_list_pattern(tokens) do
    {first, rest} = parse_receive_pattern(tokens)

    case rest do
      # Cons pattern: [h | t]
      [:pipe | rest] ->
        {tail, rest} = parse_receive_pattern(rest)
        [:close_bracket | rest] = rest
        {%AST.List{elements: [first], tail: tail}, rest}

      # Multiple elements: [a, b, c]
      [:comma | rest] ->
        {remaining, rest} = parse_pattern_list_rest(rest, [])
        {%AST.List{elements: [first | remaining], tail: nil}, rest}

      [:close_bracket | rest] ->
        {%AST.List{elements: [first], tail: nil}, rest}
    end
  end

  defp parse_pattern_list(tokens, close_token) do
    parse_pattern_list(tokens, close_token, [])
  end

  defp parse_pattern_list([token | rest], close_token, acc) when token == close_token do
    {Enum.reverse(acc), rest}
  end

  defp parse_pattern_list(tokens, close_token, acc) do
    {pattern, rest} = parse_receive_pattern(tokens)

    case rest do
      [:comma | rest] -> parse_pattern_list(rest, close_token, [pattern | acc])
      _ -> parse_pattern_list(rest, close_token, [pattern | acc])
    end
  end

  defp parse_pattern_list_rest([token | _] = tokens, acc) when token == :close_bracket do
    [:close_bracket | rest] = tokens
    {Enum.reverse(acc), rest}
  end

  defp parse_pattern_list_rest(tokens, acc) do
    {pattern, rest} = parse_receive_pattern(tokens)

    case rest do
      [:comma | rest] -> parse_pattern_list_rest(rest, [pattern | acc])
      _ -> parse_pattern_list_rest(rest, [pattern | acc])
    end
  end

  defp parse_args([:close_paren | rest], acc), do: {Enum.reverse(acc), rest}

  defp parse_args(tokens, acc) do
    {expr, rest} = parse_expr(tokens)

    case rest do
      [:comma | rest] -> parse_args(rest, [expr | acc])
      _ -> parse_args(rest, [expr | acc])
    end
  end

  defp drop_newlines([:newline | rest]), do: drop_newlines(rest)
  defp drop_newlines(tokens), do: tokens

  defp drop_only_newlines([:newline | rest]), do: drop_only_newlines(rest)
  defp drop_only_newlines(tokens), do: tokens
end
