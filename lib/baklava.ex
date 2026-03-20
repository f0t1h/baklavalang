defmodule Baklava do
  @moduledoc """
  Baklava programming language - a spatial dataflow language based on grids.
  """

  alias Baklava.{Lexer, Parser, Compiler, Runtime}

  @doc """
  Run a baklava program from source code string.
  """
  def run(source) do
    source = normalize_main_section(source)

    with {:ok, tokens} <- Lexer.tokenize(source),
         {:ok, ast} <- Parser.parse(tokens),
         {:ok, wiring} <- Compiler.compile(ast) do
      Runtime.run(wiring)
    end
  end

  defp normalize_main_section(source) do
    case String.split(source, "main:\n", parts: 2) do
      [before, main_part] ->
        normalized =
          main_part
          |> String.split("\n")
          |> Enum.map(fn line -> Regex.replace(~r/  +/, line, "\t") end)
          |> Enum.join("\n")

        before <> "main:\n" <> normalized

      _ ->
        source
    end
  end

  @doc """
  Run a baklava program from a file.
  """
  def run_file(path) do
    source = File.read!(path)
    run(source)
  end
end
