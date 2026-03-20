defmodule Baklava do
  @moduledoc """
  Baklava programming language - a spatial dataflow language based on grids.
  """

  alias Baklava.{Lexer, Parser, Compiler, Runtime}

  @doc """
  Run a baklava program from source code string.
  """
  def run(source) do
    with {:ok, tokens} <- Lexer.tokenize(source),
         {:ok, ast} <- Parser.parse(tokens),
         {:ok, wiring} <- Compiler.compile(ast) do
      Runtime.run(wiring)
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
