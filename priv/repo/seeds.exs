alias MMGO.Economy
alias MMGO.Repo
alias MMGO.Worlds
alias MMGO.Worlds.Realm

canonical_realm =
  case Repo.get_by(Realm, slug: "canonical") do
    nil ->
      Repo.insert!(%Realm{
        slug: "canonical",
        name: "Canonical Realm",
        status: :active,
        ruleset_version: 1,
        is_default: true,
        metadata: %{"description" => "Default MMGO realm for local development"}
      })

    realm ->
      realm
  end

{:ok, _treasury_account} = Economy.ensure_treasury_account(canonical_realm, 1_000_000_000)

capital_city =
  case Worlds.get_location_by_slug(canonical_realm.id, "capital-city") do
    nil ->
      {:ok, location} =
        Worlds.create_location(canonical_realm, %{
          slug: "capital-city",
          name: "Capital City",
          kind: :city,
          x: 120,
          y: 180,
          safe_zone: true
        })

      location

    location ->
      location
  end

tower =
  case Worlds.get_location_by_slug(canonical_realm.id, "the-tower") do
    nil ->
      {:ok, location} =
        Worlds.create_location(canonical_realm, %{
          slug: "the-tower",
          name: "The Tower",
          kind: :tower,
          x: 860,
          y: 260,
          safe_zone: false
        })

      location

    location ->
      location
  end

case Worlds.list_routes_for_location(capital_city.id)
     |> Enum.find(fn route ->
       route.origin_location_id == capital_city.id and route.destination_location_id == tower.id
     end) do
  nil ->
    {:ok, _route} =
      Worlds.create_route(canonical_realm, %{
        name: "Capital Road to the Tower",
        origin_location_id: capital_city.id,
        destination_location_id: tower.id,
        travel_days: 10,
        risk_level: 35,
        bidirectional: true
      })

  _route ->
    :ok
end
