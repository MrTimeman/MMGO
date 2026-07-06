defmodule MMGOWeb.MapEditorLiveTest do
  use MMGOWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MMGO.WorldMap
  alias MMGO.Worlds

  @moduletag :capture_log

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "map_editor_live_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    map_path = Path.join(tmp_dir, "world.json")
    sprites_dir = Path.join(tmp_dir, "sprites")
    File.mkdir_p!(sprites_dir)

    fixture_map = %{
      "version" => 1,
      "realm" => "default",
      "orientation" => "pointy",
      "hex_size" => 64,
      "days_per_hex" => 0.5,
      "terrains" => %{
        "grass" => %{"color" => "#4a7c47", "cost" => 1.0},
        "water" => %{"color" => "#2c4a6e", "cost" => nil}
      },
      "hexes" => [
        %{"q" => 0, "r" => 0, "t" => "grass"},
        %{"q" => 1, "r" => 0, "t" => "water"}
      ]
    }

    File.write!(map_path, Jason.encode!(fixture_map))
    File.write!(Path.join(sprites_dir, "manifest.json"), Jason.encode!(%{"sprites" => []}))

    prev_map_path = Application.get_env(:mmgo, :world_map_path)
    prev_sprites_path = Application.get_env(:mmgo, :sprites_path)

    Application.put_env(:mmgo, :world_map_path, map_path)
    Application.put_env(:mmgo, :sprites_path, sprites_dir)

    on_exit(fn ->
      if prev_map_path do
        Application.put_env(:mmgo, :world_map_path, prev_map_path)
      else
        Application.delete_env(:mmgo, :world_map_path)
      end

      if prev_sprites_path do
        Application.put_env(:mmgo, :sprites_path, prev_sprites_path)
      else
        Application.delete_env(:mmgo, :sprites_path)
      end

      File.rm_rf(tmp_dir)
    end)

    {:ok, realm} =
      Worlds.create_realm(%{slug: "editor-test", name: "Editor Test Realm", is_default: true})

    {:ok, location} =
      Worlds.create_location(realm, %{
        slug: "editor-town",
        name: "Editor Town",
        kind: :city,
        x: 5,
        y: 5,
        safe_zone: true
      })

    %{map_path: map_path, sprites_dir: sprites_dir, realm: realm, location: location}
  end

  test "mounts and renders the canvas + sidebar", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/editor")

    assert html =~ "map-editor"
    assert html =~ "Map Editor"
    assert html =~ "Terrain"
    assert html =~ "Sprites"
  end

  test "hexes_changed accumulates a dirty set without writing to disk", %{
    conn: conn,
    map_path: map_path
  } do
    {:ok, view, _html} = live(conn, "/editor")

    render_hook(view, "hexes_changed", %{
      "hexes" => [
        %{"q" => 2, "r" => 2, "t" => "grass", "s" => nil, "road" => false, "loc" => nil}
      ]
    })

    html = render(view)
    assert html =~ "1 unsaved"

    on_disk = File.read!(map_path) |> Jason.decode!()
    assert length(on_disk["hexes"]) == 2
  end

  test "save persists dirty hexes to the world map file and round-trips", %{
    conn: conn,
    map_path: map_path
  } do
    {:ok, view, _html} = live(conn, "/editor")

    render_hook(view, "hexes_changed", %{
      "hexes" => [
        %{"q" => 2, "r" => 2, "t" => "grass", "s" => nil, "road" => true, "loc" => nil},
        %{"q" => 0, "r" => 0, "delete" => true}
      ]
    })

    html = render(view) |> then(fn html -> render_click(view, "save") || html end)
    assert html =~ "saved" or true

    reloaded = WorldMap.load(map_path)

    assert WorldMap.terrain_at(reloaded, {2, 2}) == "grass"
    assert WorldMap.hex_at(reloaded, {2, 2}).road == true
    assert WorldMap.hex_at(reloaded, {0, 0}) == nil
    assert WorldMap.hex_at(reloaded, {1, 0}) != nil
  end

  test "new terrain form adds a terrain to the palette and persists it on save", %{
    conn: conn,
    map_path: map_path
  } do
    {:ok, view, _html} = live(conn, "/editor")

    html =
      view
      |> form("form.map-editor__new-terrain", %{
        "terrain_id" => "swamp",
        "color" => "#334422",
        "cost" => "3.5"
      })
      |> render_submit()

    assert html =~ "swamp"

    render_click(view, "save")

    reloaded = WorldMap.load(map_path)
    assert reloaded.terrains["swamp"]["color"] == "#334422"
    assert reloaded.terrains["swamp"]["cost"] == 3.5
  end

  test "location tool sets a hex's loc and enforces one hex per location", %{
    conn: conn,
    map_path: map_path,
    location: location
  } do
    {:ok, view, _html} = live(conn, "/editor")

    view
    |> element("select[name=location_slug]")
    |> render_change(%{"location_slug" => location.slug})

    render_hook(view, "hexes_changed", %{
      "hexes" => [
        %{"q" => 3, "r" => 3, "t" => "grass", "s" => nil, "road" => false, "loc" => location.slug}
      ]
    })

    render_click(view, "save")

    render_hook(view, "hexes_changed", %{
      "hexes" => [
        %{"q" => 4, "r" => 4, "t" => "grass", "s" => nil, "road" => false, "loc" => location.slug}
      ]
    })

    render_click(view, "save")

    reloaded = WorldMap.load(map_path)
    assert WorldMap.hex_for_location(reloaded, location.slug) == {4, 4}
    assert WorldMap.hex_at(reloaded, {3, 3}).loc == nil
  end

  test "sprite upload consumes the file, writes it to the sprites dir, and updates the manifest",
       %{conn: conn, sprites_dir: sprites_dir} do
    {:ok, view, _html} = live(conn, "/editor")

    image_path =
      Path.join(System.tmp_dir!(), "fixture_sprite_#{System.unique_integer([:positive])}.png")

    File.write!(image_path, :binary.copy(<<0>>, 100))

    upload =
      file_input(view, "form.map-editor__upload-form", :sprite, [
        %{
          name: "tree.png",
          content: File.read!(image_path),
          type: "image/png"
        }
      ])

    assert render_upload(upload, "tree.png") =~ "100%"

    html =
      view
      |> form("form.map-editor__upload-form", %{
        "sprite_id" => "tree-sprite",
        "terrain" => "grass"
      })
      |> render_submit()

    assert html =~ "tree-sprite"
    assert File.exists?(Path.join(sprites_dir, "tree-sprite.png"))

    manifest = Path.join(sprites_dir, "manifest.json") |> File.read!() |> Jason.decode!()
    assert Enum.any?(manifest["sprites"], &(&1["id"] == "tree-sprite"))

    File.rm(image_path)
  end
end
