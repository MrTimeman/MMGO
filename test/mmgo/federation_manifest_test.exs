defmodule MMGO.FederationManifestTest do
  use MMGO.DataCase, async: true

  alias MMGO.Federation.Manifest
  alias MMGO.Repo
  alias MMGO.Worlds
  alias MMGO.Worlds.Realm

  test "read_file/1 validates a realm manifest on disk" do
    path =
      Path.join(System.tmp_dir!(), "realm-manifest-#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)

    manifest = %{
      "slug" => "disk-realm",
      "name" => "Disk Realm",
      "status" => "active",
      "ruleset_version" => 1,
      "currency_code" => "GLD",
      "public_endpoint" => "https://disk-realm.test",
      "allow_migration" => true,
      "population_hint" => 10,
      "ruleset" => %{"magic_scope" => "global"},
      "metadata" => %{}
    }

    File.write!(path, Jason.encode!(manifest))

    assert {:ok, loaded_manifest} = Manifest.read_file(path)
    assert loaded_manifest["slug"] == "disk-realm"
    assert loaded_manifest["ruleset"]["magic_scope"] == "global"
  end

  test "export_realm/2 writes the current realm manifest to disk" do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true,
        currency_code: "GLD",
        public_endpoint: "https://canonical.test",
        allow_migration: true,
        ruleset: %{"magic_scope" => "tower_and_dungeon"}
      })

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    realm =
      realm
      |> Realm.changeset(%{entry_location_id: city.id})
      |> Repo.update!()

    path = Path.join(System.tmp_dir!(), "realm-export-#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, ^path} = Manifest.export_realm(realm.slug, path)

    assert {:ok, decoded} = path |> File.read!() |> Jason.decode()
    assert decoded["slug"] == "canonical"
    assert decoded["entry_location_slug"] == "capital-city"
  end

  test "apply_local_manifest/2 updates local realm rules from a manifest file" do
    {:ok, realm} =
      Worlds.create_realm(%{
        slug: "canonical",
        name: "Canonical Realm",
        is_default: true,
        currency_code: "GLD",
        public_endpoint: "https://canonical.test",
        allow_migration: true,
        ruleset: %{"magic_scope" => "tower_and_dungeon"}
      })

    {:ok, city} =
      Worlds.create_location(realm, %{
        slug: "capital-city",
        name: "Capital City",
        kind: :city,
        x: 10,
        y: 10,
        safe_zone: true
      })

    _realm =
      realm
      |> Realm.changeset(%{entry_location_id: city.id})
      |> Repo.update!()

    path = Path.join(System.tmp_dir!(), "realm-apply-#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)

    manifest = %{
      "slug" => "canonical",
      "name" => "Canonical Realm Global Magic",
      "status" => "active",
      "ruleset_version" => 2,
      "currency_code" => "GLD",
      "public_endpoint" => "https://canonical.test",
      "allow_migration" => true,
      "population_hint" => 99,
      "entry_location_slug" => "capital-city",
      "ruleset" => %{"magic_scope" => "global"},
      "metadata" => %{"variant" => "everywhere-magic"}
    }

    File.write!(path, Jason.encode!(manifest))

    assert {:ok, updated_realm} = Manifest.apply_local_manifest(path, set_default: true)
    assert updated_realm.name == "Canonical Realm Global Magic"
    assert updated_realm.ruleset["magic_scope"] == "global"
    assert updated_realm.is_default
  end

  test "apply_local_manifest/2 rejects unknown entry location slugs" do
    path =
      Path.join(System.tmp_dir!(), "realm-bad-entry-#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)

    manifest = %{
      "slug" => "broken-realm",
      "name" => "Broken Realm",
      "status" => "active",
      "ruleset_version" => 1,
      "currency_code" => "GLD",
      "public_endpoint" => "https://broken.test",
      "allow_migration" => true,
      "population_hint" => 10,
      "entry_location_slug" => "missing-city",
      "ruleset" => %{"magic_scope" => "global"},
      "metadata" => %{}
    }

    File.write!(path, Jason.encode!(manifest))

    assert {:error, changeset} = Manifest.apply_local_manifest(path)

    assert %{slug: ["entry location slug missing-city was not found locally"]} =
             errors_on(changeset)
  end
end
