alias MMGO.Economy
alias MMGO.Repo
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
