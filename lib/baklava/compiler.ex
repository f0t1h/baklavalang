defmodule Baklava.Compiler do
  @moduledoc """
  Validates the grid layout and builds the wiring map.
  Checks that adjacent sides match (output meets input).
  """

  alias Baklava.AST

  defmodule Wiring do
    @moduledoc "Describes how grids are connected."
    # connections: %{ {grid_name, direction} => target_grid_name }
    # grid_positions: %{ grid_name => {col, row} }
    # grid_defs: %{ grid_name => Grid AST node }
    defstruct [:connections, :grid_positions, :grid_defs]
  end

  @spec compile(AST.Program.t()) :: {:ok, Wiring.t()} | {:error, String.t()}
  def compile(%AST.Program{grids: grids, main: main}) do
    grid_defs = Map.new(grids, fn g -> {g.name, g} end)

    # Build position map from main layout
    grid_positions = build_positions(main)

    # Validate all placed grids are defined
    with :ok <- validate_definitions(grid_positions, grid_defs),
         # Analyze each grid for its side usage (which sides are inputs, which are outputs)
         side_map <- analyze_all_sides(grid_defs),
         # Build and validate connections
         {:ok, connections} <- build_connections(grid_positions, side_map) do
      {:ok, %Wiring{
        connections: connections,
        grid_positions: grid_positions,
        grid_defs: grid_defs
      }}
    end
  end

  defp build_positions(%AST.Main{rows: rows}) do
    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, row_idx} ->
      row
      |> Enum.with_index()
      |> Enum.filter(fn {name, _} -> name != nil end)
      |> Enum.map(fn {name, col_idx} -> {name, {col_idx, row_idx}} end)
    end)
    |> Map.new()
  end

  defp validate_definitions(grid_positions, grid_defs) do
    undefined =
      grid_positions
      |> Map.keys()
      |> Enum.reject(&Map.has_key?(grid_defs, &1))

    case undefined do
      [] -> :ok
      names -> {:error, "undefined grids: #{Enum.join(names, ", ")}"}
    end
  end

  @doc """
  Analyze a grid's AST to determine which sides it uses and how (input/output).
  Returns %{ grid_name => %{ direction => :input | :output } }
  """
  def analyze_all_sides(grid_defs) do
    Map.new(grid_defs, fn {name, grid} ->
      {name, analyze_sides(grid.body)}
    end)
  end

  defp analyze_sides(node, acc \\ %{})

  defp analyze_sides(%AST.Block{stmts: stmts}, acc) do
    Enum.reduce(stmts, acc, &analyze_sides/2)
  end

  defp analyze_sides(%AST.Emit{direction: dir}, acc) do
    Map.put(acc, dir, :output)
  end

  defp analyze_sides(%AST.Receive{direction: dir, body: body}, acc) do
    acc = Map.put(acc, dir, :input)
    analyze_sides(body, acc)
  end

  defp analyze_sides(%AST.If{then: then_body, else: else_body}, acc) do
    acc = analyze_sides(then_body, acc)
    if else_body, do: analyze_sides(else_body, acc), else: acc
  end

  defp analyze_sides(_, acc), do: acc

  @directions_offsets %{
    right: {1, 0},
    left: {-1, 0},
    up: {0, -1},
    down: {0, 1}
  }

  @opposite %{
    right: :left,
    left: :right,
    up: :down,
    down: :up
  }

  defp build_connections(grid_positions, side_map) do
    pos_to_grid = Map.new(grid_positions, fn {name, pos} -> {pos, name} end)

    errors =
      grid_positions
      |> Enum.flat_map(fn {name, {cx, cy}} ->
        sides = Map.get(side_map, name, %{})

        sides
        |> Enum.filter(fn {_dir, role} -> role == :output end)
        |> Enum.flat_map(fn {dir, :output} ->
          {dx, dy} = @directions_offsets[dir]
          neighbor_pos = {cx + dx, cy + dy}

          case Map.get(pos_to_grid, neighbor_pos) do
            nil ->
              ["grid '#{name}' emits #{dir} but no grid is adjacent there"]

            neighbor ->
              neighbor_sides = Map.get(side_map, neighbor, %{})
              opposite = @opposite[dir]

              case Map.get(neighbor_sides, opposite) do
                :input -> []
                nil -> ["grid '#{name}' emits #{dir} to '#{neighbor}', but '#{neighbor}' has no #{opposite} input"]
                :output -> ["grid '#{name}' emits #{dir} to '#{neighbor}', but '#{neighbor}' also emits #{opposite} (output meets output)"]
              end
          end
        end)
      end)

    case errors do
      [] ->
        connections =
          grid_positions
          |> Enum.flat_map(fn {name, {cx, cy}} ->
            sides = Map.get(side_map, name, %{})

            sides
            |> Enum.filter(fn {_dir, role} -> role == :output end)
            |> Enum.map(fn {dir, :output} ->
              {dx, dy} = @directions_offsets[dir]
              neighbor_pos = {cx + dx, cy + dy}
              neighbor = Map.fetch!(pos_to_grid, neighbor_pos)
              {{name, dir}, neighbor}
            end)
          end)
          |> Map.new()

        {:ok, connections}

      _ ->
        {:error, Enum.join(errors, "\n")}
    end
  end
end
