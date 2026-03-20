defmodule Baklava.CLI do
  def main(args) do
    case args do
      [path] ->
        case Baklava.run_file(path) do
          :ok -> :ok
          {:error, msg} -> IO.puts(:stderr, "error: #{msg}")
        end

      _ ->
        IO.puts(:stderr, "usage: gridlan <file.grid>")
    end
  end
end
