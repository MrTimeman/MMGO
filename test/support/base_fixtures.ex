defmodule MMGO.BaseFixtures do
  @moduledoc false

  alias MMGO.Economy
  alias MMGO.Inventory
  alias MMGO.Inventory.ItemTemplate
  alias MMGO.Repo

  @default_funding 2_000
  @default_material_quantity 10

  def fund_base_acquisition!(realm, character, opts \\ []) do
    funding = Keyword.get(opts, :funding, @default_funding)
    material_quantity = Keyword.get(opts, :material_quantity, @default_material_quantity)

    {:ok, _treasury} = Economy.ensure_treasury_account(realm, 100_000)
    {:ok, _funding} = Economy.grant_from_treasury(realm, character, funding)

    template =
      Repo.get_by(ItemTemplate, code: "construction_material") ||
        create_construction_material!()

    {:ok, _materials} =
      Inventory.grant_item(character, template, %{quantity: material_quantity})

    character
  end

  defp create_construction_material! do
    {:ok, template} =
      Inventory.create_item_template(%{
        code: "construction_material",
        name: "Construction Material",
        item_type: :ingredient,
        stackable: true,
        weight: 2,
        max_durability: 0,
        nutrition_units: 0,
        actions: [],
        metadata: %{}
      })

    template
  end
end
