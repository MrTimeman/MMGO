defmodule MMGO.Reputation do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Economy
  alias MMGO.Repo
  alias MMGO.Reputation.{CrimeRecord, Profile}
  alias MMGO.Travel.Clock
  alias MMGO.Worlds.Realm

  def profile_for_character(character_id) when is_binary(character_id) do
    Repo.get_by(Profile, character_id: character_id)
  end

  def profile_for_character!(character_id) when is_binary(character_id) do
    Repo.get_by!(Profile, character_id: character_id)
  end

  def ensure_profile(%Character{} = character) do
    case profile_for_character(character.id) do
      %Profile{} = profile ->
        {:ok, profile}

      nil ->
        %Profile{}
        |> Profile.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          reputation_score: 0,
          crime_count: 0,
          outstanding_fine: 0,
          npc_hostility_level: 0,
          metadata: %{}
        })
        |> Repo.insert()
    end
  end

  def list_crimes_for_character(character_id) when is_binary(character_id) do
    Repo.all(
      from crime in CrimeRecord,
        where: crime.character_id == ^character_id,
        order_by: [desc: crime.inserted_at]
    )
  end

  def market_access_allowed?(character_id) when is_binary(character_id) do
    case profile_for_character(character_id) do
      nil ->
        true

      %Profile{} = profile ->
        is_nil(profile.market_ban_until) or
          DateTime.compare(profile.market_ban_until, DateTime.utc_now()) != :gt
    end
  end

  def record_crime(
        character_or_repo,
        maybe_character_or_type,
        maybe_type_or_attrs \\ nil,
        maybe_attrs \\ %{}
      )

  def record_crime(%Character{} = character, crime_type, attrs, _unused)
      when is_map(attrs) or is_list(attrs) do
    record_crime(Repo, character, crime_type, attrs)
  end

  def record_crime(repo, %Character{} = character, crime_type, attrs) do
    attrs = normalize_attrs(attrs)
    now = attrs["recorded_at"] || DateTime.utc_now()
    severity = attrs["severity"] || default_severity(crime_type)
    reputation_delta = attrs["reputation_delta"] || default_reputation_delta(crime_type, severity)
    fine_amount = attrs["fine_amount"] || default_fine_amount(crime_type, severity)

    market_ban_game_days =
      attrs["market_ban_game_days"] || default_market_ban_game_days(crime_type, severity)

    status = normalize_crime_status(attrs["status"])

    repo.transaction(fn ->
      profile =
        Profile
        |> where([profile], profile.character_id == ^character.id)
        |> lock("FOR UPDATE")
        |> repo.one()

      profile =
        case profile do
          nil ->
            %Profile{}
            |> Profile.changeset(%{
              character_id: character.id,
              realm_id: character.realm_id,
              reputation_score: 0,
              crime_count: 0,
              outstanding_fine: 0,
              npc_hostility_level: 0,
              metadata: %{}
            })
            |> repo.insert!()

          %Profile{} = profile ->
            profile
        end

      crime_record =
        %CrimeRecord{}
        |> CrimeRecord.changeset(%{
          character_id: character.id,
          realm_id: character.realm_id,
          profile_id: profile.id,
          crime_type: normalize_crime_type(crime_type),
          status: status,
          severity: severity,
          reputation_delta: reputation_delta,
          fine_amount: fine_amount,
          recorded_at: now,
          metadata: attrs["metadata"] || %{}
        })
        |> repo.insert!()

      market_ban_until =
        next_market_ban_until(profile.market_ban_until, now, market_ban_game_days)

      updated_score = profile.reputation_score + reputation_delta
      updated_fine = profile.outstanding_fine + fine_amount
      updated_crime_count = profile.crime_count + 1

      updated_profile =
        profile
        |> Profile.changeset(%{
          reputation_score: updated_score,
          crime_count: updated_crime_count,
          outstanding_fine: updated_fine,
          npc_hostility_level: hostility_level(updated_score, updated_crime_count),
          market_ban_until: market_ban_until
        })
        |> repo.update!()

      %{profile: updated_profile, crime_record: crime_record}
    end)
    |> normalize_transaction_result()
  end

  def record_black_market_default(%Character{} = seller, total_price, metadata \\ %{})
      when is_integer(total_price) do
    record_crime(seller, :black_market_default, %{
      severity: 25,
      fine_amount: max(div(total_price, 2), 10),
      market_ban_game_days: 28,
      metadata: metadata
    })
  end

  def pay_fine(%Character{} = character, amount \\ nil) do
    with %Profile{} = profile <- profile_for_character(character.id),
         true <- profile.outstanding_fine > 0 do
      {:ok, character_account} = Economy.ensure_character_account(character)
      realm = Repo.get!(Realm, character.realm_id)
      %_{} = treasury_account = Economy.treasury_account_for_realm(realm.id)
      payment_amount = amount || min(character_account.current_balance, profile.outstanding_fine)

      cond do
        payment_amount <= 0 ->
          {:error, fine_changeset("payment amount must be greater than zero")}

        character_account.current_balance < payment_amount ->
          {:error, fine_changeset("character lacks the required funds")}

        true ->
          Repo.transaction(fn ->
            profile =
              Profile
              |> where([profile], profile.id == ^profile.id)
              |> lock("FOR UPDATE")
              |> Repo.one!()

            {:ok, ledger_result} =
              Economy.transfer(character_account, treasury_account, payment_amount, %{
                entry_type: "tax",
                source: "crime_fine",
                character_id: character.id
              })

            updated_profile =
              profile
              |> Profile.changeset(%{
                outstanding_fine: max(profile.outstanding_fine - payment_amount, 0),
                market_ban_until:
                  maybe_clear_market_ban(
                    profile.market_ban_until,
                    payment_amount,
                    profile.outstanding_fine
                  )
              })
              |> Repo.update!()

            %{profile: updated_profile, economy: ledger_result}
          end)
          |> normalize_transaction_result()
      end
    else
      nil -> {:error, fine_changeset("character has no reputation profile")}
      false -> {:error, fine_changeset("character has no outstanding fines")}
    end
  end

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_attrs(attrs) when is_list(attrs),
    do: Enum.into(attrs, %{}, fn {key, value} -> {to_string(key), value} end)

  defp normalize_attrs(_attrs), do: %{}

  defp normalize_crime_type(crime_type) when is_atom(crime_type), do: Atom.to_string(crime_type)
  defp normalize_crime_type(crime_type) when is_binary(crime_type), do: crime_type

  defp normalize_crime_status("resolved"), do: :resolved
  defp normalize_crime_status(:resolved), do: :resolved
  defp normalize_crime_status(_status), do: :open

  defp default_severity(:black_market_default), do: 20
  defp default_severity(_crime_type), do: 10

  defp default_reputation_delta(:black_market_default, severity), do: -severity
  defp default_reputation_delta(_crime_type, severity), do: -div(severity, 2)

  defp default_fine_amount(:black_market_default, severity), do: severity * 2
  defp default_fine_amount(_crime_type, severity), do: severity

  defp default_market_ban_game_days(:black_market_default, severity), do: max(severity, 7)
  defp default_market_ban_game_days(_crime_type, severity), do: max(div(severity, 2), 3)

  defp next_market_ban_until(nil, _now, 0), do: nil

  defp next_market_ban_until(existing_until, now, market_ban_game_days) do
    candidate = Clock.arrival_at(now, market_ban_game_days)

    cond do
      is_nil(existing_until) -> candidate
      DateTime.compare(existing_until, candidate) == :gt -> existing_until
      true -> candidate
    end
  end

  defp hostility_level(reputation_score, crime_count) do
    max(div(abs(reputation_score), 10) + crime_count, 0)
  end

  defp maybe_clear_market_ban(market_ban_until, payment_amount, outstanding_fine) do
    if outstanding_fine - payment_amount <= 0 do
      nil
    else
      market_ban_until
    end
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp fine_changeset(message) do
    %Profile{}
    |> Changeset.change()
    |> Changeset.add_error(:outstanding_fine, message)
  end
end
