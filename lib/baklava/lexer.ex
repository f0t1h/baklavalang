defmodule Baklava.Lexer do
  @moduledoc """
  Tokenizer for baklavalang.
  """

  @type token ::
          {:ident, String.t()}
          | {:int, integer()}
          | {:string, String.t()}
          | :open_bracket
          | :close_bracket
          | :open_brace
          | :close_brace
          | :open_paren
          | :close_paren
          | :hash
          | :dollar
          | :pipe_right     # |>
          | :left_pipe      # <|
          | :pipe_up        # |^
          | :pipe_down      # |v
          | :arrow           # =>
          | :dot_dot         # ..
          | :comma
          | :newline
          | :tab
          | :colon
          | :plus
          | :minus
          | :star
          | :slash
          | :equal
          | :less
          | :greater
          | :less_equal
          | :greater_equal
          | :equal_equal
          | :bang_equal
          | :kw_if
          | :kw_else
          | :kw_main
          | :kw_true
          | :kw_false

  @keywords %{
    "if" => :kw_if,
    "else" => :kw_else,
    "halt" => :kw_halt,
    "main" => :kw_main,
    "true" => :kw_true,
    "false" => :kw_false,
    "let" => :kw_let
  }

  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, String.t()}
  def tokenize(source) do
    tokenize(source, [])
  end

  defp tokenize("", acc), do: {:ok, Enum.reverse(acc)}

  # Whitespace (spaces only, not tabs or newlines)
  defp tokenize(" " <> rest, acc), do: tokenize(rest, acc)
  defp tokenize("\r" <> rest, acc), do: tokenize(rest, acc)

  # Tab and newline are significant
  defp tokenize("\t" <> rest, acc), do: tokenize(rest, [:tab | acc])
  defp tokenize("\n" <> rest, acc), do: tokenize(rest, [:newline | acc])

  # Relay symbols (4 chars, only meaningful in main: section)
  # Left input
  defp tokenize("-->>" <> rest, acc), do: tokenize(rest, [{:relay, :left, :right} | acc])
  defp tokenize("-->^" <> rest, acc), do: tokenize(rest, [{:relay, :left, :up} | acc])
  defp tokenize("-->v" <> rest, acc), do: tokenize(rest, [{:relay, :left, :down} | acc])
  # Right input
  defp tokenize("<<--" <> rest, acc), do: tokenize(rest, [{:relay, :right, :left} | acc])
  defp tokenize("^<--" <> rest, acc), do: tokenize(rest, [{:relay, :right, :up} | acc])
  defp tokenize("v<--" <> rest, acc), do: tokenize(rest, [{:relay, :right, :down} | acc])
  # Top input
  defp tokenize("<--v" <> rest, acc), do: tokenize(rest, [{:relay, :top, :left} | acc])
  defp tokenize("v-->" <> rest, acc), do: tokenize(rest, [{:relay, :top, :right} | acc])
  defp tokenize("vvvv" <> rest, acc), do: tokenize(rest, [{:relay, :top, :down} | acc])
  # Bottom input
  defp tokenize("<--^" <> rest, acc), do: tokenize(rest, [{:relay, :bottom, :left} | acc])
  defp tokenize("^-->" <> rest, acc), do: tokenize(rest, [{:relay, :bottom, :right} | acc])
  defp tokenize("^^^^" <> rest, acc), do: tokenize(rest, [{:relay, :bottom, :up} | acc])

  # Two-character tokens
  defp tokenize("|>" <> rest, acc), do: tokenize(rest, [:pipe_right | acc])
  defp tokenize("<|" <> rest, acc), do: tokenize(rest, [:left_pipe | acc])
  defp tokenize("|^" <> rest, acc), do: tokenize(rest, [:pipe_up | acc])
  defp tokenize("|v" <> rest, acc), do: tokenize(rest, [:pipe_down | acc])
  defp tokenize("=>" <> rest, acc), do: tokenize(rest, [:arrow | acc])
  defp tokenize(".." <> rest, acc), do: tokenize(rest, [:dot_dot | acc])
  defp tokenize("<=" <> rest, acc), do: tokenize(rest, [:less_equal | acc])
  defp tokenize(">=" <> rest, acc), do: tokenize(rest, [:greater_equal | acc])
  defp tokenize("==" <> rest, acc), do: tokenize(rest, [:equal_equal | acc])
  defp tokenize("!=" <> rest, acc), do: tokenize(rest, [:bang_equal | acc])

  # Comments: // to end of line
  defp tokenize("//" <> rest, acc) do
    rest = skip_until_newline(rest)
    tokenize(rest, acc)
  end

  # Single-character tokens
  defp tokenize("[" <> rest, acc), do: tokenize(rest, [:open_bracket | acc])
  defp tokenize("]" <> rest, acc), do: tokenize(rest, [:close_bracket | acc])
  defp tokenize("{" <> rest, acc), do: tokenize(rest, [:open_brace | acc])
  defp tokenize("}" <> rest, acc), do: tokenize(rest, [:close_brace | acc])
  defp tokenize("(" <> rest, acc), do: tokenize(rest, [:open_paren | acc])
  defp tokenize(")" <> rest, acc), do: tokenize(rest, [:close_paren | acc])
  defp tokenize("#" <> rest, acc), do: tokenize(rest, [:hash | acc])
  defp tokenize("$" <> rest, acc), do: tokenize(rest, [:dollar | acc])
  defp tokenize("," <> rest, acc), do: tokenize(rest, [:comma | acc])
  defp tokenize("." <> rest, acc), do: tokenize(rest, [:dot | acc])
  defp tokenize(":" <> rest, acc), do: tokenize(rest, [:colon | acc])
  defp tokenize("|" <> rest, acc), do: tokenize(rest, [:pipe | acc])
  defp tokenize("+" <> rest, acc), do: tokenize(rest, [:plus | acc])
  defp tokenize("-" <> rest, acc), do: tokenize(rest, [:minus | acc])
  defp tokenize("*" <> rest, acc), do: tokenize(rest, [:star | acc])
  defp tokenize("/" <> rest, acc), do: tokenize(rest, [:slash | acc])
  defp tokenize("=" <> rest, acc), do: tokenize(rest, [:equal | acc])
  defp tokenize("<" <> rest, acc), do: tokenize(rest, [:less | acc])
  defp tokenize(">" <> rest, acc), do: tokenize(rest, [:greater | acc])

  # String literals
  defp tokenize("\"" <> rest, acc) do
    case read_string(rest, "") do
      {:ok, str, rest} -> tokenize(rest, [{:string, str} | acc])
      :error -> {:error, "unterminated string"}
    end
  end

  # Numbers
  defp tokenize(<<c, _::binary>> = source, acc) when c in ?0..?9 do
    {num, rest} = read_number(source)
    tokenize(rest, [{:int, num} | acc])
  end

  # Identifiers and keywords
  defp tokenize(<<c, _::binary>> = source, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {name, rest} = read_ident(source)
    token = Map.get(@keywords, name, {:ident, name})
    tokenize(rest, [token | acc])
  end

  defp tokenize(<<c, _::binary>>, _acc) do
    {:error, "unexpected character: #{<<c>>}"}
  end

  defp skip_until_newline(""), do: ""
  defp skip_until_newline("\n" <> _ = rest), do: rest
  defp skip_until_newline(<<_, rest::binary>>), do: skip_until_newline(rest)

  defp read_string("", _acc), do: :error
  defp read_string("\"" <> rest, acc), do: {:ok, acc, rest}
  defp read_string("\\\\" <> rest, acc), do: read_string(rest, acc <> "\\")
  defp read_string("\\n" <> rest, acc), do: read_string(rest, acc <> "\n")
  defp read_string("\\t" <> rest, acc), do: read_string(rest, acc <> "\t")
  defp read_string("\\\"" <> rest, acc), do: read_string(rest, acc <> "\"")
  defp read_string(<<c, rest::binary>>, acc), do: read_string(rest, acc <> <<c>>)

  defp read_number(source), do: read_number(source, 0)
  defp read_number(<<c, rest::binary>>, n) when c in ?0..?9, do: read_number(rest, n * 10 + (c - ?0))
  defp read_number(rest, n), do: {n, rest}

  defp read_ident(source), do: read_ident(source, "")
  defp read_ident(<<c, rest::binary>>, acc) when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_, do: read_ident(rest, acc <> <<c>>)
  defp read_ident(rest, acc), do: {acc, rest}
end
