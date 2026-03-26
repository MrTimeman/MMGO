defmodule MMGO.Worlds do
  import Ecto.Query, warn: false

  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  def list_realms do
    Repo.all(from realm in Realm, order_by: [asc: realm.inserted_at])
  end

  def get_realm!(id), do: Repo.get!(Realm, id)

  def get_realm_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Realm, slug: slug)
  end

  def get_default_realm do
    Repo.get_by(Realm, is_default: true)
  end

  def get_default_realm! do
    Repo.get_by!(Realm, is_default: true)
  end

  def create_realm(attrs \\ %{}) do
    %Realm{}
    |> Realm.changeset(attrs)
    |> Repo.insert()
  end

  def change_realm(%Realm{} = realm, attrs \\ %{}) do
    Realm.changeset(realm, attrs)
  end
end
