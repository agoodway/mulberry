defmodule Mulberry.Research.MultiModuleTest do
  # Can't use async with application env changes
  use ExUnit.Case, async: false

  alias Mulberry.Research.Chain
  alias Mulberry.Search.{Brave, Reddit}

  describe "Chain.get_search_modules/1" do
    test "returns normalized modules from search_modules field" do
      chain = %Chain{
        search_modules: [
          %{module: Brave, options: %{}, weight: 1.0},
          %{module: Reddit, options: %{sort: "top"}, weight: 1.5}
        ]
      }

      modules = Chain.get_search_modules(chain)

      assert length(modules) == 2
      assert Enum.at(modules, 0).module == Brave
      assert Enum.at(modules, 1).module == Reddit
      assert Enum.at(modules, 1).weight == 1.5
    end

    test "converts single search_module to modules list" do
      chain = %Chain{
        search_module: Reddit,
        search_module_options: %{sort: "new"}
      }

      modules = Chain.get_search_modules(chain)

      assert length(modules) == 1
      assert Enum.at(modules, 0).module == Reddit
      assert Enum.at(modules, 0).options == %{sort: "new"}
      assert Enum.at(modules, 0).weight == 1.0
    end

    test "defaults to Brave search when no modules configured" do
      chain = %Chain{}

      modules = Chain.get_search_modules(chain)

      assert length(modules) == 1
      assert Enum.at(modules, 0).module == Mulberry.Search.Brave
      assert Enum.at(modules, 0).options == %{}
      assert Enum.at(modules, 0).weight == 1.0
    end
  end

  describe "Research module configuration" do
    test "accepts search_modules option" do
      opts = [
        search_modules: [
          %{module: Brave, options: %{}},
          %{module: Reddit, options: %{sort: "top"}, weight: 1.5}
        ]
      ]

      # This tests that the option is accepted without error
      assert {:ok, chain} = build_test_chain(opts)
      assert is_list(chain.search_modules)
      assert length(chain.search_modules) == 2
    end

    test "accepts single search_module option for backward compatibility" do
      opts = [
        search_module: Reddit,
        search_module_options: %{sort: "new"}
      ]

      # This tests backward compatibility
      assert {:ok, chain} = build_test_chain(opts)
      assert chain.search_module == Reddit
      assert chain.search_module_options == %{sort: "new"}
    end

    test "normalizes module configurations" do
      opts = [
        search_modules: [
          %{"module" => Brave, "options" => %{}, "weight" => 2.0},
          %{module: Reddit, options: %{}}
        ]
      ]

      assert {:ok, chain} = build_test_chain(opts)
      modules = Chain.get_search_modules(chain)

      # All modules should be normalized
      assert Enum.all?(modules, fn m ->
               Map.has_key?(m, :module) and
                 Map.has_key?(m, :options) and
                 Map.has_key?(m, :weight)
             end)
    end
  end

  defp build_test_chain(opts) do
    # Build a chain with test options
    base_attrs = %{
      strategy: :web,
      max_sources: 5,
      search_depth: 1
    }

    attrs = Enum.into(opts, base_attrs)
    Chain.new(attrs)
  end
end
