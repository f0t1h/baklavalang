defmodule Baklava.Runtime do
  @moduledoc """
  Executes a compiled baklavalang program.
  Each grid becomes an Elixir process running compiled BEAM code.
  """

  alias Baklava.Compiler.Wiring

  def run(%Wiring{connections: connections, grid_defs: grid_defs, grid_positions: grid_positions}) do
    parent = self()

    # Compile all grids to Elixir modules
    grid_modules = Baklava.Codegen.compile_all(grid_defs)

    grid_pids =
      grid_positions
      |> Map.keys()
      |> Map.new(fn name ->
        pid = spawn(fn ->
          receive do
            {:channels, channels} ->
              mod = Map.fetch!(grid_modules, name)
              mod.run(channels, parent)
              for {{:out, _dir}, pid} <- channels, do: send(pid, :eof)
              send(parent, {:grid_done, name})
          end
        end)
        {name, pid}
      end)

    # Build channel maps
    grid_channels =
      grid_positions
      |> Map.keys()
      |> Map.new(fn name ->
        sides = Baklava.Compiler.analyze_all_sides(grid_defs) |> Map.get(name, %{})

        channels =
          sides
          |> Enum.map(fn {dir, role} ->
            case role do
              :output ->
                target_name = Map.fetch!(connections, {name, dir})
                target_pid = Map.fetch!(grid_pids, target_name)
                {{:out, dir}, target_pid}

              :input ->
                {{:in, dir}, :mailbox}
            end
          end)
          |> Map.new()

        {name, channels}
      end)

    for {name, pid} <- grid_pids do
      send(pid, {:channels, Map.fetch!(grid_channels, name)})
    end

    wait_for_grids(Map.keys(grid_positions), grid_pids)
  end

  defp wait_for_grids([], _pids), do: :ok

  defp wait_for_grids(remaining, pids) do
    receive do
      {:grid_done, name} ->
        wait_for_grids(List.delete(remaining, name), pids)

      :halt ->
        for {_n, pid} <- pids, Process.alive?(pid), do: send(pid, :halt)
        wait_for_shutdown(Map.values(pids))
    end
  end

  defp wait_for_shutdown([]), do: :ok
  defp wait_for_shutdown(pids) do
    pids
    |> Enum.filter(&Process.alive?/1)
    |> case do
      [] -> :ok
      alive ->
        Process.sleep(1)
        wait_for_shutdown(alive)
    end
  end
end
