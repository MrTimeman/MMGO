alias MMGO.Repo
alias MMGO.Worlds.Realm

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

  _realm ->
    :ok
end
