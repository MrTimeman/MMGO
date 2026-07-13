defmodule MMGO.TowerSeedTopologyTest do
  use MMGO.DataCase, async: false

  alias MMGO.Dungeons
  alias MMGO.Dungeons.{Floor, Node}
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  test "the canonical seed keeps a seven-floor Tower graph with routes and side resources" do
    run_seed!()

    realm = Repo.get_by!(Realm, slug: "canonical")
    dungeon = Dungeons.get_dungeon_by_slug(realm.id, "tower-dungeon")

    floors =
      Floor
      |> where([floor], floor.dungeon_id == ^dungeon.id)
      |> order_by([floor], asc: floor.number)
      |> Repo.all()

    nodes =
      Node
      |> join(:inner, [node], floor in Floor, on: floor.id == node.floor_id)
      |> where([_node, floor], floor.dungeon_id == ^dungeon.id)
      |> Repo.all()

    nodes_by_slug = Map.new(nodes, &{&1.slug, &1})
    links = Dungeons.list_links_for_dungeon(dungeon.id)

    assert Enum.map(floors, & &1.number) == Enum.to_list(1..7)

    assert Enum.all?(floors, fn floor ->
             Enum.count(nodes, &(&1.floor_id == floor.id)) >= 3
           end)

    assert %Node{kind: :rest, metadata: %{"topology_role" => "side_resource"}} =
             nodes_by_slug["provisioning-nook"]

    assert %Node{metadata: %{"topology_role" => "dead_end_resource"}} =
             nodes_by_slug["cinder-cache"]

    assert %Node{kind: :rest, metadata: %{"topology_role" => "side_resource"}} =
             nodes_by_slug["quiet-well"]

    assert %Node{metadata: %{"topology_role" => "dead_end_resource"}} =
             nodes_by_slug["heart-sanctum"]

    for slug <- ["provisioning-nook", "cinder-cache", "quiet-well", "heart-sanctum"] do
      node = Map.fetch!(nodes_by_slug, slug)

      assert Enum.count(links, fn link ->
               link.from_node_id == node.id or link.to_node_id == node.id
             end) == 1
    end

    shortcut =
      find_link!(
        links,
        nodes_by_slug["floor-2-ascent"],
        nodes_by_slug["floor-2-descent"]
      )

    assert shortcut.travel_cost == 1
    assert shortcut.metadata["route_role"] == "shortcut"
    assert shortcut.metadata["route_shape"] == "hidden_connection"

    assert find_link!(
             links,
             nodes_by_slug["floor-4-ascent"],
             nodes_by_slug["sealed-annex"]
           ).metadata["route_role"] == "alternate_passage"

    assert find_link!(
             links,
             nodes_by_slug["sealed-annex"],
             nodes_by_slug["floor-4-descent"]
           ).metadata["route_role"] == "alternate_passage"

    assert find_link!(
             links,
             nodes_by_slug["floor-6-ascent"],
             nodes_by_slug["mirror-bridge"]
           ).metadata["route_role"] == "alternate_passage"

    assert find_link!(
             links,
             nodes_by_slug["mirror-bridge"],
             nodes_by_slug["floor-6-descent"]
           ).metadata["route_role"] == "alternate_passage"

    counts_before_repeat = {length(nodes), length(links)}
    run_seed!()

    repeated_nodes =
      Node
      |> join(:inner, [node], floor in Floor, on: floor.id == node.floor_id)
      |> where([_node, floor], floor.dungeon_id == ^dungeon.id)
      |> Repo.all()

    assert {length(repeated_nodes), length(Dungeons.list_links_for_dungeon(dungeon.id))} ==
             counts_before_repeat
  end

  defp find_link!(links, left, right) do
    Enum.find(links, fn link ->
      (link.from_node_id == left.id and link.to_node_id == right.id) or
        (link.bidirectional and link.from_node_id == right.id and link.to_node_id == left.id)
    end) || raise "expected a link between #{left.slug} and #{right.slug}"
  end

  defp run_seed! do
    Code.eval_file(Path.expand("../../priv/repo/seeds.exs", __DIR__))
  end
end
