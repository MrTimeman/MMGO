defmodule MMGO.WorldsTest do
  use MMGO.DataCase, async: true

  alias MMGO.Worlds
  alias MMGO.Worlds.Realm

  test "create_realm/1 persists a default realm" do
    assert {:ok, %Realm{} = realm} =
             Worlds.create_realm(%{
               slug: "canonical",
               name: "Canonical Realm",
               is_default: true,
               metadata: %{"region" => "tower"}
             })

    assert realm.slug == "canonical"
    assert realm.is_default
    assert realm.status == :active
    assert Worlds.get_default_realm().id == realm.id
  end
end
