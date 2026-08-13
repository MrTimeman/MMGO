defmodule MMGO.Arena do
  @moduledoc """
  Fair, self-contained arena progression built on real characters, grimoires,
  spells, and the shared combat engine.

  Arena profiles never touch inventory, realm currency, travel, or PvP stakes.
  Their character exists as a technical anchor so spellcraft and combat can be
  reused without giving world progression an advantage.
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.{Account, Character, CharacterProfiles}

  alias MMGO.Arena.{
    Ladder,
    Match,
    MatchMember,
    Profile,
    Quests,
    RoomRules,
    TitleChallenge,
    Titles
  }

  alias MMGO.Combat
  alias MMGO.Combat.ArenaEvents
  alias MMGO.Combat.Combat, as: CombatSchema
  alias MMGO.Grimoires.{Grimoire, GrimoireEntry}
  alias MMGO.Repo
  alias MMGO.Spells
  alias MMGO.Spells.SchoolQuirk
  alias MMGO.Worlds
  alias MMGO.Worlds.{Location, Realm}

  @combat_level 100

  # Ranked pairing starts inside this rating band and widens with every step of
  # waiting, so a thin queue still resolves.
  @rating_match_tolerance 120
  @rating_tolerance_step_seconds 15
  @rating_tolerance_step 40
  @max_rating_tolerance 1_200
  @initial_rating 1_000
  @season_xp %{win: 100, loss: 60, draw: 75}

  @starter_spells %{
    fire: %{
      name: "Arena Ember",
      formula: "ignis arena",
      targeting: :enemy,
      delivery_form: :single_target,
      effects: [%{applies_to: :target, state: "burning", intensity: 12, variance: 2, duration: 2}]
    },
    water: %{
      name: "Arena Rime",
      formula: "aqua arena",
      targeting: :enemy,
      delivery_form: :cone,
      effects: [%{applies_to: :target, state: "frozen", intensity: 9, variance: 1, duration: 2}]
    },
    earth: %{
      name: "Arena Bulwark",
      formula: "terra arena",
      targeting: :self,
      delivery_form: :self,
      effects: [
        %{applies_to: :caster, state: "shielded", intensity: 15, variance: 0, duration: 2}
      ]
    },
    air: %{
      name: "Arena Gale",
      formula: "aer arena",
      targeting: :enemy,
      delivery_form: :beam,
      effects: [
        %{applies_to: :target, state: "staggered", intensity: 10, variance: 2, duration: 1}
      ]
    },
    life: %{
      name: "Arena Renewal",
      formula: "vita arena",
      targeting: :self,
      delivery_form: :self,
      effects: [
        %{applies_to: :caster, state: "regenerating", intensity: 12, variance: 1, duration: 2}
      ]
    },
    death: %{
      name: "Arena Wither",
      formula: "mors arena",
      targeting: :enemy,
      delivery_form: :single_target,
      effects: [%{applies_to: :target, state: "impact", intensity: 16, variance: 3, duration: 0}]
    },
    chaos: %{
      name: "Arena Fracture",
      formula: "chaos arena",
      targeting: :enemy,
      delivery_form: :sphere,
      effects: [%{applies_to: :target, state: "exposed", intensity: 11, variance: 4, duration: 2}]
    },
    order: %{
      name: "Arena Axiom",
      formula: "ordo arena",
      targeting: :self,
      delivery_form: :self,
      effects: [
        %{applies_to: :caster, state: "empowered", intensity: 12, variance: 0, duration: 2}
      ]
    }
  }

  def schools, do: Profile.schools()
  def combat_level, do: @combat_level

  @doc """
  The loadout slot count a profile may keep.

  Books grow with the ladder, and the two seats sit above it: 45 slots belong
  to the Champion and the Deputy alone.
  """
  def grimoire_capacity_for(%Profile{} = profile) do
    cond do
      Titles.holds_seat?(profile, :champion) -> Ladder.grimoire_capacity(:champion)
      Titles.holds_seat?(profile, :deputy) -> Ladder.deputy_grimoire_capacity()
      true -> Ladder.grimoire_capacity(profile.division)
    end
  end

  def grimoire_capacity_for(_profile), do: Ladder.grimoire_capacity(:initiate)

  @doc """
  Raises every arena loadout the profile owns to the given capacity.

  Promotion goes up and never down, so a book that already holds entries is
  never squeezed by a demotion.
  """
  def raise_grimoire_capacity(%Profile{} = profile, capacity) when is_integer(capacity) do
    query =
      from g in Grimoire,
        where: g.owner_character_id == ^profile.character_id,
        where: fragment("COALESCE(?->>'arena', '') = 'true'", g.metadata)

    Repo.update_all(query, set: [capacity: capacity])
  end

  def get_profile!(id) when is_binary(id) do
    Profile
    |> Repo.get!(id)
    |> preload_profile()
  end

  @doc "The profile behind an id, or nil."
  def get_profile(id) when is_binary(id) do
    case Repo.get(Profile, id) do
      nil -> nil
      profile -> preload_profile(profile)
    end
  end

  def get_profile(_id), do: nil

  @doc """
  The account's current arena profile.

  A player may keep several profiles to experiment with school combinations;
  the most recently created one stands in until a profile is explicitly chosen.
  """
  def get_profile_by_account(account_id) when is_binary(account_id) do
    Profile
    |> where([profile], profile.account_id == ^account_id)
    |> order_by([profile], desc: profile.inserted_at, desc: profile.id)
    |> limit(1)
    |> Repo.one()
    |> preload_profile()
  end

  def get_profile_by_account(_account_id), do: nil

  @doc "Every arena profile the account owns, oldest first."
  def list_profiles_for_account(account_id) when is_binary(account_id) do
    Profile
    |> where([profile], profile.account_id == ^account_id)
    |> order_by([profile], asc: profile.inserted_at, asc: profile.id)
    |> Repo.all()
    |> Enum.map(&preload_profile/1)
  end

  def list_profiles_for_account(_account_id), do: []

  def get_profile_for_account(%Account{id: account_id}), do: get_profile_by_account(account_id)
  def get_profile_for_account(account_id), do: get_profile_by_account(account_id)

  def get_profile_by_character(character_id) when is_binary(character_id) do
    Profile
    |> Repo.get_by(character_id: character_id)
    |> preload_profile()
  end

  def get_profile_by_character(_character_id), do: nil

  def schools(%Profile{} = profile), do: profile.schools

  @doc """
  The competitive division a profile holds.

  A profile reports the division it actually holds, which lags rating on the way
  down by the ladder's demotion buffer. A bare rating reports what that rating
  alone would earn.
  """
  def rank(%Profile{division: division}) when not is_nil(division), do: division
  def rank(%Profile{rating: rating}), do: rank(rating)
  def rank(rating) when is_integer(rating), do: Ladder.division_for_rating(rating)

  @doc "Creates one active level-100 arena character with exactly three chosen schools."
  def create_profile(%Account{} = account, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      account = lock_account!(account.id)

      if account.status != :active do
        Repo.rollback(profile_error(:account_id, "account is inactive"))
      end

      realm = Worlds.get_default_realm() || Repo.rollback(:default_realm_not_found)
      anchor = arena_anchor(realm) || Repo.rollback(:arena_anchor_not_found)
      schools = normalize_schools(attrs["schools"])

      character =
        %Character{
          account_id: account.id,
          realm_id: realm.id,
          current_location_id: anchor.id
        }
        |> Character.changeset(%{
          name: arena_character_name(account, realm.id, attrs["name"]),
          status: :active,
          level: @combat_level,
          xp: 0,
          metadata: %{
            "profile_kind" => "arena",
            "hidden_presence" => true,
            "arena_equalized_level" => @combat_level,
            "unlocked_schools" => Enum.map(schools, &to_string/1)
          }
        })
        |> insert_or_rollback()

      profile =
        %Profile{account_id: account.id, character_id: character.id}
        |> Profile.changeset(%{
          schools: schools,
          rating: @initial_rating,
          metadata: %{"provisioning_version" => 1}
        })
        |> insert_or_rollback()

      spells = Enum.map(schools, &create_starter_spell!(character, &1))
      _grimoire = create_starter_grimoire!(character, spells)

      preload_profile(profile)
    end)
  end

  def create_profile(account_id, attrs) when is_binary(account_id) and is_map(attrs) do
    case Repo.get(Account, account_id) do
      %Account{} = account -> create_profile(account, attrs)
      nil -> {:error, :account_not_found}
    end
  end

  @doc "Creates another free, weightless top-capacity arena loadout draft."
  def create_draft_grimoire(%Profile{} = profile, attrs \\ %{}) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    Repo.transaction(fn ->
      profile = lock_profile!(profile.id)
      character = Repo.get!(Character, profile.character_id)
      ensure_arena_character!(character)

      count =
        Repo.aggregate(
          from(grimoire in Grimoire,
            where: grimoire.owner_character_id == ^character.id
          ),
          :count
        )

      name = attrs["name"] || "Arena Grimoire #{count + 1}"

      %Grimoire{}
      |> arena_grimoire_changeset(
        character,
        name,
        :draft,
        %{
          "arena" => true,
          "free" => true,
          "top_tier" => true,
          "editable" => true,
          "loadout_rules" => "limited"
        },
        grimoire_capacity_for(profile)
      )
      |> insert_or_rollback()
    end)
    |> broadcast_profile_result(profile.id, :grimoire_created)
  end

  @doc "Selects one owned arena grimoire as the combat loadout."
  def activate_grimoire(%Profile{} = profile, %Grimoire{} = selected) do
    Repo.transaction(fn ->
      profile = lock_profile!(profile.id)

      grimoires =
        Grimoire
        |> where([grimoire], grimoire.owner_character_id == ^profile.character_id)
        |> order_by([grimoire], asc: grimoire.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      selected = Enum.find(grimoires, &(&1.id == selected.id))

      cond do
        is_nil(selected) or not arena_grimoire?(selected) ->
          Repo.rollback(grimoire_error(:owner_character_id, "is not an arena grimoire"))

        not grimoire_has_spells?(selected.id) ->
          Repo.rollback(grimoire_error(:entries, "grimoire must contain at least one spell"))

        true ->
          Enum.each(grimoires, fn grimoire ->
            status = if grimoire.id == selected.id, do: :active, else: inactive_status(grimoire)

            if status != grimoire.status do
              grimoire |> Changeset.change(status: status) |> Repo.update!()
            end
          end)

          selected
          |> Repo.reload!()
          |> Repo.preload(entries: :spell)
      end
    end)
    |> broadcast_profile_result(profile.id, :grimoire_activated)
  end

  def get_match!(id) when is_binary(id) do
    Match
    |> Repo.get!(id)
    |> preload_match()
  end

  def get_match_by_code(code) when is_binary(code) do
    Match
    |> Repo.get_by(code: normalize_room_code(code))
    |> preload_match()
  end

  def get_match_by_code(_code), do: nil

  @doc "Returns the profile's current room, queue entry, or live Arena match."
  def active_match_for_profile(%Profile{id: profile_id}),
    do: active_match_for_profile(profile_id)

  def active_match_for_profile(profile_id) when is_binary(profile_id) do
    Match
    |> join(:inner, [match], member in MatchMember, on: member.match_id == match.id)
    |> where(
      [match, member],
      member.profile_id == ^profile_id and match.status in [:forming, :queued, :active]
    )
    |> order_by([match, _member], desc: match.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> preload_match()
  end

  def active_match_for_profile(_profile), do: nil

  def list_rankings(season \\ 1, limit \\ 50)

  def list_rankings(season, limit)
      when is_integer(season) and season > 0 and is_integer(limit) and limit > 0 do
    Repo.all(
      from profile in Profile,
        where: profile.season == ^season,
        order_by: [desc: profile.rating, desc: profile.wins, asc: profile.matches_played],
        limit: ^min(limit, 100),
        preload: [:account, :character]
    )
  end

  def list_rankings(_season, _limit), do: []

  def list_open_rooms(limit \\ 20)

  def list_open_rooms(limit) when is_integer(limit) and limit > 0 do
    Match
    |> where([match], match.mode == :custom and match.status == :forming)
    |> order_by([match], desc: match.inserted_at)
    |> limit(^min(limit, 50))
    |> Repo.all()
    |> Enum.map(&preload_match/1)
  end

  def list_open_rooms(_limit), do: []

  @doc "Creates a friendly custom room from 1v1 through 5v5."
  def create_custom_room(%Profile{} = host, attrs \\ %{}) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    result =
      Repo.transaction(fn ->
        host = lock_profile!(host.id)
        ensure_profile_available!(host.id)
        team_size = normalize_integer(attrs["team_size"], 1)
        seed = normalize_integer(attrs["seed"], new_seed())
        policy = attrs["event_policy"] || "random"
        requested_codes = List.wrap(attrs["event_codes"])
        schedule = event_schedule!(policy, requested_codes, seed)

        match =
          %Match{host_profile_id: host.id, realm_id: host.character.realm_id}
          |> Match.changeset(%{
            mode: :custom,
            status: :forming,
            team_size: team_size,
            event_policy: schedule["policy"],
            event_codes: schedule["codes"],
            settings: sanitize_settings(attrs["settings"]),
            metadata: %{"friendly" => true},
            code: new_room_code(),
            seed: seed
          })
          |> insert_or_rollback()

        insert_member!(match, host, :a, 1, false)
        preload_match(match)
      end)

    broadcast_match_result(result, :room_created)
  end

  @doc "Joins an open custom room, choosing a balanced team unless one is requested."
  def join_custom_room(code, %Profile{} = profile, attrs \\ %{})
      when is_binary(code) and is_map(attrs) do
    attrs = stringify_keys(attrs)

    result =
      Repo.transaction(fn ->
        profile = lock_profile!(profile.id)
        ensure_profile_available!(profile.id)
        match = lock_match_by_code!(code)
        ensure_forming_custom!(match)
        members = lock_members(match.id)

        if Enum.any?(members, &(&1.profile_id == profile.id)) do
          Repo.rollback(:already_joined)
        end

        if length(members) >= match.team_size * 2 do
          Repo.rollback(:room_full)
        end

        team = choose_team(attrs["team"], members, match.team_size)
        position = next_position(members, team, match.team_size) || Repo.rollback(:team_full)
        insert_member!(match, profile, team, position, false)
        preload_match(match)
      end)

    broadcast_match_result(result, :member_joined)
  end

  @doc "Moves a member to the other (or requested) team and clears readiness."
  def switch_team(match_or_id, %Profile{} = profile, requested_team \\ nil) do
    result =
      Repo.transaction(fn ->
        match = lock_match!(match_id(match_or_id))
        ensure_forming_custom!(match)
        members = lock_members(match.id)

        member =
          Enum.find(members, &(&1.profile_id == profile.id)) || Repo.rollback(:not_a_member)

        team = normalize_team(requested_team) || opposite_team(member.team)

        if team == member.team do
          member
        else
          position = next_position(members, team, match.team_size) || Repo.rollback(:team_full)

          member
          |> MatchMember.changeset(%{team: team, position: position, ready: false})
          |> Repo.update!()
        end

        match |> Repo.reload!() |> preload_match()
      end)

    broadcast_match_result(result, :member_switched_team)
  end

  @doc "Toggles one custom-room member's ready state."
  def toggle_ready(match_or_id, %Profile{} = profile) do
    result =
      Repo.transaction(fn ->
        match = lock_match!(match_id(match_or_id))
        ensure_forming_custom!(match)

        member =
          match.id
          |> lock_members()
          |> Enum.find(&(&1.profile_id == profile.id))
          |> Kernel.||(Repo.rollback(:not_a_member))

        member
        |> MatchMember.changeset(%{ready: not member.ready})
        |> Repo.update!()

        match |> Repo.reload!() |> preload_match()
      end)

    broadcast_match_result(result, :readiness_changed)
  end

  @doc "Leaves a forming custom room; when the host leaves, the room closes for everyone."
  def leave_custom_room(match_or_id, %Profile{} = profile) do
    result =
      Repo.transaction(fn ->
        match = lock_match!(match_id(match_or_id))
        ensure_forming_custom!(match)
        members = lock_members(match.id)

        member =
          Enum.find(members, &(&1.profile_id == profile.id)) || Repo.rollback(:not_a_member)

        if match.host_profile_id == profile.id do
          match
          |> Match.changeset(%{status: :cancelled})
          |> Repo.update!()
        else
          Repo.delete!(member)

          members
          |> Enum.reject(&(&1.id == member.id))
          |> Enum.filter(& &1.ready)
          |> Enum.each(fn member ->
            member
            |> MatchMember.changeset(%{ready: false})
            |> Repo.update!()
          end)

          Repo.reload!(match)
        end
        |> preload_match()
      end)

    broadcast_match_result(result, :member_left)
  end

  @doc "Starts a full, equally sized custom match once every member is ready."
  def start_custom_room(match_or_id, %Profile{} = host) do
    result =
      Repo.transaction(fn ->
        match = lock_match!(match_id(match_or_id))
        ensure_forming_custom!(match)

        if match.host_profile_id != host.id do
          Repo.rollback(:host_only)
        end

        members = lock_members(match.id)
        ensure_teams_ready!(match, members)
        start_match!(match, members)
      end)

    broadcast_match_result(result, :match_started)
  end

  @doc "Enters the transaction-safe, equalized 1v1 ranked queue."
  def queue_ranked(%Profile{} = profile) do
    result =
      Repo.transaction(fn ->
        ranked_queue_lock!()
        profile = lock_profile!(profile.id)

        case queued_match_for_profile(profile.id) do
          %Match{} = existing ->
            preload_match(existing)

          nil ->
            ensure_profile_available!(profile.id)

            case oldest_ranked_candidate(profile.id, profile.rating) do
              %Match{} = candidate ->
                candidate = lock_match!(candidate.id)
                _members = lock_members(candidate.id)
                insert_member!(candidate, profile, :b, 1, true)
                start_match!(candidate, lock_members(candidate.id))

              nil ->
                create_ranked_queue_entry!(profile)
            end
        end
      end)

    broadcast_match_result(result, :ranked_queue_changed)
  end

  @doc """
  What the queue looks like right now.

  A player waiting alone in a silent queue cannot tell whether the arena is
  empty or broken. This is the difference: how many are waiting, how many are
  already fighting, and how long the last pairings actually took.
  """
  def queue_snapshot(season \\ 1) do
    waiting =
      Match
      |> where([match], match.mode == :ranked and match.status == :queued)
      |> Repo.aggregate(:count)

    fighting =
      Match
      |> where([match], match.status == :active)
      |> Repo.aggregate(:count)

    %{
      season: season,
      waiting: waiting,
      fighting: fighting,
      estimated_wait_seconds: estimated_wait_seconds()
    }
  end

  # Measured, not guessed: the median of how long recent ranked entries actually
  # sat in the queue before a match started. Nil when nothing has paired yet.
  defp estimated_wait_seconds do
    Match
    |> where([match], match.mode == :ranked and not is_nil(match.started_at))
    |> where([match], not is_nil(match.queued_at))
    |> order_by([match], desc: match.started_at)
    |> limit(20)
    |> select([match], fragment("EXTRACT(EPOCH FROM (? - ?))", match.started_at, match.queued_at))
    |> Repo.all()
    |> case do
      [] ->
        nil

      waits ->
        waits
        |> Enum.map(&(&1 |> Decimal.to_float() |> round() |> max(0)))
        |> Enum.sort()
        |> median()
    end
  end

  defp median(sorted) do
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(sorted, middle)
    else
      div(Enum.at(sorted, middle - 1) + Enum.at(sorted, middle), 2)
    end
  end

  def cancel_ranked_queue(%Profile{} = profile) do
    result =
      Repo.transaction(fn ->
        ranked_queue_lock!()

        match = queued_match_for_profile(profile.id) || Repo.rollback(:not_queued)
        match = lock_match!(match.id)

        match
        |> Match.changeset(%{status: :cancelled})
        |> Repo.update!()
        |> preload_match()
      end)

    broadcast_match_result(result, :ranked_queue_changed)
  end

  @doc """
  Opens the fight that settles a title challenge.

  A title bout is played under ordinary arena rules — rank gates, grimoires and
  mana all as in ranked play — but it moves no rating: the stake is the seat.
  Neither side queues for it and neither side may decline it, so the match is
  created already under way.
  """
  def start_title_bout(%TitleChallenge{status: :open} = challenge) do
    result =
      Repo.transaction(fn ->
        challenge = Repo.preload(challenge, [:challenger_profile, :defender_profile])
        challenger = lock_profile!(challenge.challenger_profile_id)
        defender = lock_profile!(challenge.defender_profile_id)

        ensure_profile_available!(challenger.id)
        ensure_profile_available!(defender.id)

        seed = new_seed()
        schedule = event_schedule!(:random, [], seed)

        match =
          %Match{host_profile_id: challenger.id, realm_id: challenger.character.realm_id}
          |> Match.changeset(%{
            mode: :custom,
            status: :forming,
            team_size: 1,
            event_policy: schedule["policy"],
            event_codes: schedule["codes"],
            code: new_room_code(),
            settings: %{
              "room_name" => "Бой за титул",
              "description" => "Вызов на титул: отказаться нельзя.",
              "turn_seconds" => 60,
              "rules" => RoomRules.defaults() |> stringify_rank_cap()
            },
            metadata: %{
              "friendly" => false,
              "title_challenge_id" => challenge.id,
              "title_seat" => to_string(challenge.seat)
            },
            seed: seed
          })
          |> insert_or_rollback()

        insert_member!(match, challenger, :a, 1, true)
        insert_member!(match, defender, :b, 1, true)

        match = start_match!(match, lock_members(match.id))

        case Titles.attach_match(challenge, match.id) do
          {:ok, _challenge} -> match
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    broadcast_match_result(result, :title_bout_started)
  end

  def start_title_bout(%TitleChallenge{}), do: {:error, :challenge_not_open}

  @doc "Idempotently applies arena progression when its shared combat finishes."
  def settle_match(%CombatSchema{} = combat) do
    result =
      Repo.transaction(fn ->
        match =
          Match
          |> where([match], match.combat_id == ^combat.id)
          |> lock("FOR UPDATE")
          |> Repo.one()
          |> Kernel.||(Repo.rollback(:arena_match_not_found))

        cond do
          match.status == :finished ->
            preload_match(match)

          match.status != :active ->
            Repo.rollback(:arena_match_not_active)

          combat.status != :finished ->
            Repo.rollback(:combat_not_finished)

          true ->
            settle_active_match!(match, combat)
        end
      end)

    broadcast_match_result(result, :match_finished)
  end

  def settle_match(%Match{combat_id: combat_id}) when is_binary(combat_id) do
    combat_id |> Combat.get_combat!() |> settle_match()
  end

  def settle_match(%Match{}), do: {:error, :combat_not_started}

  def room_topic(match_id) when is_binary(match_id), do: "arena:room:#{match_id}"
  def queue_topic(season \\ 1), do: "arena:queue:#{season}"
  def profile_topic(profile_id) when is_binary(profile_id), do: "arena:profile:#{profile_id}"

  def subscribe_room(match_id) when is_binary(match_id),
    do: Phoenix.PubSub.subscribe(MMGO.PubSub, room_topic(match_id))

  def subscribe_queue(season \\ 1),
    do: Phoenix.PubSub.subscribe(MMGO.PubSub, queue_topic(season))

  def subscribe_profile(profile_id) when is_binary(profile_id),
    do: Phoenix.PubSub.subscribe(MMGO.PubSub, profile_topic(profile_id))

  defp create_ranked_queue_entry!(profile) do
    seed = new_seed()
    schedule = event_schedule!(:random, [], seed)

    match =
      %Match{host_profile_id: profile.id, realm_id: profile.character.realm_id}
      |> Match.changeset(%{
        mode: :ranked,
        status: :queued,
        team_size: 1,
        event_policy: schedule["policy"],
        event_codes: schedule["codes"],
        metadata: %{
          "rating_at_queue" => profile.rating,
          "division_at_queue" => to_string(rank(profile))
        },
        seed: seed,
        queued_at: DateTime.utc_now()
      })
      |> insert_or_rollback()

    insert_member!(match, profile, :a, 1, true)
    preload_match(match)
  end

  defp start_match!(match, members) do
    members = Repo.preload(members, profile: :character)
    schedule = event_schedule!(match.event_policy, match.event_codes, match.seed)

    participants =
      Enum.map(members, fn member ->
        grimoire =
          Repo.get_by(Grimoire,
            owner_character_id: member.profile.character_id,
            status: :active
          ) || Repo.rollback({:active_grimoire_required, member.profile.id})

        %{
          character_id: member.profile.character_id,
          side: to_string(member.team),
          position: member.position - 1,
          combat_level: @combat_level,
          # The arena profile fighting this match carries its own division,
          # not the strongest one its owner holds elsewhere.
          rank: rank(member.profile),
          max_mana: Titles.mana_pool_for(member.profile),
          grimoire_id: grimoire.id,
          metadata: %{"arena_profile_id" => member.profile.id}
        }
      end)

    shared_hp = 100 * match.team_size
    realm = Repo.get!(Realm, match.realm_id)
    initial_event = ArenaEvents.event_for_turn(schedule, 1)
    initial_event_tags = ArenaEvents.active_tags(schedule, 1)
    turn_seconds = if match.mode == :custom, do: match.settings["turn_seconds"]

    combat_attrs = %{
      participants: participants,
      sides: %{
        "a" => %{"label" => "Team A", "shared_hp" => shared_hp, "max_shared_hp" => shared_hp},
        "b" => %{"label" => "Team B", "shared_hp" => shared_hp, "max_shared_hp" => shared_hp}
      },
      seed: match.seed,
      turn_seconds: turn_seconds,
      environment_tags: initial_event_tags,
      metadata: %{
        "arena_match_id" => match.id,
        "arena_mode" => to_string(match.mode),
        RoomRules.metadata_key() => match_rules(match),
        "arena_events" => schedule,
        "arena_active_event_code" => initial_event && initial_event["code"],
        "arena_active_event_tags" => initial_event_tags,
        "arena_hp_per_member" => 100,
        "turn_seconds" => turn_seconds,
        "friendly" => match.mode == :custom
      }
    }

    combat =
      case Combat.create_arena_match(realm, combat_attrs) do
        {:ok, %{combat: combat}} -> combat
        {:error, reason} -> Repo.rollback(reason)
        {:error, _step, reason, _changes} -> Repo.rollback(reason)
      end

    match
    |> Changeset.change(combat_id: combat.id)
    |> Match.changeset(%{
      status: :active,
      started_at: DateTime.utc_now()
    })
    |> Repo.update!()
    |> preload_match()
  end

  # Only a friendly room may bend the rules. Ranked play is always the ordinary
  # arena, whatever a host once wrote into its settings.
  defp match_rules(%Match{mode: :custom, settings: settings}) when is_map(settings) do
    settings |> Map.get("rules", %{}) |> RoomRules.normalize() |> stringify_rank_cap()
  end

  defp match_rules(%Match{}), do: RoomRules.defaults()

  defp stringify_rank_cap(rules) do
    Map.update!(rules, "rank_cap", fn
      nil -> nil
      cap -> to_string(cap)
    end)
  end

  defp settle_active_match!(match, combat) do
    members =
      match.id
      |> lock_members()
      |> Repo.preload(profile: :character)

    winner_team = normalize_winner_team(combat.winner_side)
    ratings = Map.new(members, &{&1.profile_id, &1.profile.rating})

    Enum.each(members, fn member ->
      outcome = outcome(member.team, winner_team)
      profile = member.profile
      settled = settled_standing(match, member, members, ratings, outcome)
      season_xp_gained = Map.fetch!(@season_xp, outcome)

      stats = %{
        rating: settled.rating,
        division: settled.division,
        placements_remaining: placements_after(match, profile),
        season_xp: profile.season_xp + season_xp_gained,
        wins: profile.wins + if(outcome == :win, do: 1, else: 0),
        losses: profile.losses + if(outcome == :loss, do: 1, else: 0),
        draws: profile.draws + if(outcome == :draw, do: 1, else: 0),
        matches_played: profile.matches_played + 1
      }

      profile |> Profile.changeset(stats) |> Repo.update!()

      member
      |> MatchMember.changeset(%{
        outcome: outcome,
        rating_before: profile.rating,
        rating_after: settled.rating,
        division_before: profile.division,
        division_after: settled.division,
        season_xp_gained: season_xp_gained
      })
      |> Repo.update!()

      # Quests and the day streak read the same settled match; they never ask
      # the player to claim anything. Only ranked play counts — a pair of
      # friends taking turns losing to each other is not a day's work.
      if match.mode == :ranked do
        Quests.record_match(Repo.get!(Profile, profile.id), outcome)
      end

      # A seat holder who fights is not away, whatever the calendar says.
      Titles.touch_activity(profile, profile.season)
    end)

    settle_title_bout!(match, members, winner_team)

    match
    |> Match.changeset(%{
      status: :finished,
      winner_team: winner_team,
      finished_at: combat.finished_at || DateTime.utc_now()
    })
    |> Repo.update!()
    |> preload_match()
  end

  # A title bout settles a seat rather than a rating. A draw leaves the
  # challenge open: the seat is only won by beating the holder.
  defp settle_title_bout!(%Match{metadata: metadata}, members, winner_team)
       when is_map(metadata) do
    with challenge_id when is_binary(challenge_id) <- Map.get(metadata, "title_challenge_id"),
         %TitleChallenge{status: :open} = challenge <- Repo.get(TitleChallenge, challenge_id),
         %MatchMember{} = winner <- Enum.find(members, &(&1.team == winner_team)) do
      case Titles.settle(challenge, winner.profile_id) do
        {:ok, _settled} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    else
      _no_title_bout -> :ok
    end
  end

  defp settle_title_bout!(_match, _members, _winner_team), do: :ok

  # Friendly rooms never move the ladder.
  defp settled_standing(%Match{mode: :custom}, member, _members, _ratings, _outcome),
    do: %{rating: member.profile.rating, division: member.profile.division}

  defp settled_standing(%Match{mode: :ranked}, member, members, ratings, outcome) do
    opponents = Enum.reject(members, &(&1.team == member.team))

    opponent_average =
      Enum.sum(Enum.map(opponents, &Map.fetch!(ratings, &1.profile_id))) / length(opponents)

    expected = 1.0 / (1.0 + :math.pow(10.0, (opponent_average - member.profile.rating) / 400.0))
    score = %{win: 1.0, draw: 0.5, loss: 0.0} |> Map.fetch!(outcome)

    Ladder.settle(member.profile.rating, member.profile.division, expected, score,
      placement?: placement?(member.profile)
    )
  end

  defp placement?(%Profile{placements_remaining: remaining}) when is_integer(remaining),
    do: remaining > 0

  defp placement?(_profile), do: false

  # Only ranked play counts toward placements: a friendly room tells the ladder
  # nothing about where someone belongs.
  defp placements_after(%Match{mode: :ranked}, %Profile{placements_remaining: remaining})
       when is_integer(remaining),
       do: max(remaining - 1, 0)

  defp placements_after(_match, %Profile{placements_remaining: remaining}), do: remaining || 0

  defp outcome(_team, nil), do: :draw
  defp outcome(team, team), do: :win
  defp outcome(_team, _winner_team), do: :loss

  defp normalize_winner_team("a"), do: :a
  defp normalize_winner_team(:a), do: :a
  defp normalize_winner_team("b"), do: :b
  defp normalize_winner_team(:b), do: :b
  defp normalize_winner_team(_winner), do: nil

  defp ensure_teams_ready!(match, members) do
    a_count = Enum.count(members, &(&1.team == :a))
    b_count = Enum.count(members, &(&1.team == :b))

    cond do
      a_count != match.team_size or b_count != match.team_size -> Repo.rollback(:teams_not_full)
      not Enum.all?(members, & &1.ready) -> Repo.rollback(:members_not_ready)
      true -> :ok
    end
  end

  defp ensure_profile_available!(profile_id) do
    busy? =
      Repo.exists?(
        from member in MatchMember,
          join: match in Match,
          on: match.id == member.match_id,
          where:
            member.profile_id == ^profile_id and
              match.status in [:forming, :queued, :active]
      )

    if busy?, do: Repo.rollback(:profile_busy), else: :ok
  end

  defp queued_match_for_profile(profile_id) do
    Repo.one(
      from match in Match,
        join: member in MatchMember,
        on: member.match_id == match.id,
        where:
          member.profile_id == ^profile_id and match.mode == :ranked and
            match.status == :queued,
        limit: 1
    )
  end

  # Rank is what a spell is gated on, and rating is what earns rank, so pairing
  # on rating pairs like against like without a second dial. The band widens the
  # longer a candidate has waited, so a thin queue still resolves.
  defp oldest_ranked_candidate(profile_id, rating) do
    Repo.one(
      from match in Match,
        join: member in MatchMember,
        on: member.match_id == match.id,
        where:
          match.mode == :ranked and match.status == :queued and
            member.profile_id != ^profile_id,
        where:
          fragment(
            "ABS(COALESCE((? ->> 'rating_at_queue')::int, ?) - ?) <= LEAST(? + (EXTRACT(EPOCH FROM (NOW() - ?)) / ?)::int * ?, ?)",
            match.metadata,
            ^@initial_rating,
            ^rating,
            ^@rating_match_tolerance,
            match.queued_at,
            ^@rating_tolerance_step_seconds,
            ^@rating_tolerance_step,
            ^@max_rating_tolerance
          ),
        order_by: [asc: match.queued_at, asc: match.id],
        limit: 1
    )
  end

  defp event_schedule!(policy, codes, seed) do
    case ArenaEvents.schedule(policy, codes, seed) do
      {:ok, schedule} ->
        schedule

      {:error, :invalid_event_policy} ->
        Repo.rollback(match_error(:event_policy, "is invalid"))

      {:error, :invalid_event_code} ->
        Repo.rollback(match_error(:event_codes, "contains an invalid event"))

      {:error, :invalid_seed} ->
        Repo.rollback(match_error(:seed, "is invalid"))
    end
  end

  defp insert_member!(match, profile, team, position, ready) do
    %MatchMember{match_id: match.id, profile_id: profile.id}
    |> MatchMember.changeset(%{
      team: team,
      position: position,
      ready: ready,
      joined_at: DateTime.utc_now()
    })
    |> insert_or_rollback()
  end

  defp lock_account!(account_id) do
    Account |> where([account], account.id == ^account_id) |> lock("FOR UPDATE") |> Repo.one!()
  end

  defp lock_profile!(profile_id) do
    Profile
    |> where([profile], profile.id == ^profile_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
    |> Repo.preload(:character)
  end

  defp lock_match!(match_id) do
    Match |> where([match], match.id == ^match_id) |> lock("FOR UPDATE") |> Repo.one!()
  end

  defp lock_match_by_code!(code) do
    Match
    |> where([match], match.code == ^normalize_room_code(code))
    |> lock("FOR UPDATE")
    |> Repo.one()
    |> Kernel.||(Repo.rollback(:room_not_found))
  end

  defp lock_members(match_id) do
    MatchMember
    |> where([member], member.match_id == ^match_id)
    |> order_by([member], asc: member.team, asc: member.position, asc: member.id)
    |> lock("FOR UPDATE")
    |> Repo.all()
  end

  defp ranked_queue_lock! do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", ["mmgo-arena-ranked-queue"])
  end

  defp ensure_forming_custom!(%Match{mode: :custom, status: :forming}), do: :ok
  defp ensure_forming_custom!(%Match{mode: :custom}), do: Repo.rollback(:room_not_forming)
  defp ensure_forming_custom!(%Match{}), do: Repo.rollback(:not_a_custom_room)

  @doc """
  Re-stocks every arena profile whose book is empty.

  The release that wipes spells cannot do this itself: a migration runs against
  the schema as it stood at its own point in the sequence, while the structs it
  would need are always at their newest. The seed runs after every migration has
  landed, so it belongs here.

  Only empty books are touched, which makes this safe to run on every deploy.
  """
  def restock_empty_arena_books do
    Profile
    |> Repo.all()
    |> Enum.filter(&arena_book_empty?/1)
    |> Enum.map(fn profile ->
      {:ok, _grimoire} = reissue_starter_spells(profile)
      profile.id
    end)
  end

  defp arena_book_empty?(%Profile{character_id: character_id}) do
    not Repo.exists?(
      from entry in GrimoireEntry,
        join: grimoire in Grimoire,
        on: grimoire.id == entry.grimoire_id,
        where: grimoire.owner_character_id == ^character_id
    )
  end

  @doc """
  Re-issues the three school starter spells to an existing profile.

  Used by the release that wipes every spell: a player who logs in afterwards
  finds a working book rather than an empty one. The spells are bound into the
  profile's active grimoire directly — the ordinary writability rule protects a
  book from its owner, not from the arena re-stocking it.
  """
  def reissue_starter_spells(%Profile{} = profile) do
    Repo.transaction(fn ->
      character = Repo.get!(Character, profile.character_id)
      spells = Enum.map(profile.schools, &create_starter_spell!(character, &1))

      case Repo.get_by(Grimoire, owner_character_id: character.id, status: :active) do
        %Grimoire{} = grimoire -> bind_starter_spells!(grimoire, spells)
        nil -> create_starter_grimoire!(character, spells, grimoire_capacity_for(profile))
      end
    end)
  end

  defp bind_starter_spells!(%Grimoire{} = grimoire, spells) do
    occupied =
      GrimoireEntry
      |> where([entry], entry.grimoire_id == ^grimoire.id)
      |> select([entry], entry.slot_index)
      |> Repo.all()

    next_slot = (Enum.max(occupied, fn -> 0 end) || 0) + 1

    spells
    |> Enum.with_index(next_slot)
    |> Enum.each(fn {spell, slot_index} ->
      %GrimoireEntry{}
      |> GrimoireEntry.changeset(%{
        grimoire_id: grimoire.id,
        spell_id: spell.id,
        slot_index: slot_index
      })
      |> insert_or_rollback()
    end)

    grimoire
  end

  defp create_starter_spell!(character, school) do
    attrs =
      @starter_spells
      |> Map.fetch!(school)
      |> Map.merge(%{
        school: school,
        school_quirk: SchoolQuirk.for_school(school),
        description:
          "Arena-issued #{school} spell. Replace it with your own formula whenever you like.",
        power: 1,
        fatigue_cost: 4,
        cooldown_turns: 0,
        tags: ["arena", "starter"],
        narrative_tags: ["arena-issued"],
        environment_tags: [to_string(school)],
        environment_mode: :none,
        failure_profile: %{
          difficulty: 5,
          base_success_rate: 92,
          partial_success_rate: 6,
          backlash_damage: 0,
          volatility: 5
        }
      })

    case Spells.create_spell(character, attrs) do
      {:ok, spell} -> spell
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp create_starter_grimoire!(character, spells, capacity \\ nil) do
    capacity = capacity || Ladder.grimoire_capacity(:initiate)

    grimoire =
      %Grimoire{}
      |> arena_grimoire_changeset(
        character,
        "Arena Grimoire",
        :draft,
        %{
          "arena" => true,
          "free" => true,
          "top_tier" => true,
          "starter" => true,
          "loadout_rules" => "limited"
        },
        capacity
      )
      |> insert_or_rollback()

    spells
    |> Enum.with_index(1)
    |> Enum.each(fn {spell, slot_index} ->
      %GrimoireEntry{}
      |> GrimoireEntry.changeset(%{
        grimoire_id: grimoire.id,
        spell_id: spell.id,
        slot_index: slot_index
      })
      |> insert_or_rollback()
    end)

    grimoire |> Changeset.change(status: :active) |> Repo.update!()
  end

  defp arena_grimoire_changeset(grimoire, character, name, status, metadata, capacity) do
    grimoire
    |> Changeset.change(%{
      owner_character_id: character.id,
      realm_id: character.realm_id,
      name: name,
      status: status,
      capacity: capacity,
      weight: 0,
      metadata: metadata
    })
    |> Changeset.validate_required([
      :owner_character_id,
      :realm_id,
      :name,
      :status,
      :capacity,
      :weight
    ])
    |> Changeset.validate_length(:name, min: 3, max: 120)
  end

  defp arena_anchor(%Realm{} = realm) do
    cond do
      is_binary(realm.entry_location_id) -> Repo.get(Location, realm.entry_location_id)
      tower = Worlds.get_location_by_slug(realm.id, "the-tower") -> tower
      true -> realm.id |> Worlds.list_locations_for_realm() |> List.first()
    end
  end

  defp arena_character_name(account, realm_id, requested_name) do
    base =
      case requested_name do
        name when is_binary(name) and byte_size(name) > 0 -> String.trim(name)
        _other -> "#{account.display_name} Arena"
      end
      |> String.slice(0, 40)

    if Repo.exists?(
         from character in Character,
           where: character.realm_id == ^realm_id and character.name == ^base
       ) do
      suffix = account.id |> String.replace("-", "") |> String.slice(0, 4)
      "#{String.slice(base, 0, 35)}-#{suffix}"
    else
      base
    end
  end

  defp normalize_schools(schools) when is_list(schools) do
    Enum.map(schools, fn
      school when is_atom(school) ->
        school

      school when is_binary(school) ->
        Enum.find(Profile.schools(), &(to_string(&1) == school)) || school

      school ->
        school
    end)
  end

  defp normalize_schools(_schools), do: []

  defp sanitize_settings(settings) when is_map(settings) do
    settings = stringify_keys(settings)

    %{
      "turn_seconds" => normalize_turn_seconds(settings["turn_seconds"]),
      "room_name" => sanitize_room_copy(settings["room_name"], "Дружеский круг", 60),
      "description" => sanitize_room_copy(settings["description"], "", 180),
      "rules" => sanitize_rules(settings["rules"])
    }
  end

  defp sanitize_settings(_settings), do: %{}

  # The host's special rules are normalised once, here, and the resolved set is
  # what the combat is started with. Nothing downstream reads the raw map.
  defp sanitize_rules(rules) do
    rules |> RoomRules.normalize() |> stringify_rank_cap()
  end

  defp normalize_turn_seconds(seconds) do
    seconds
    |> normalize_integer(45)
    |> then(fn parsed -> if parsed in [30, 45, 60, 90, 120], do: parsed, else: 45 end)
  end

  defp sanitize_room_copy(value, fallback, max_length) when is_binary(value) do
    case value |> String.trim() |> String.slice(0, max_length) do
      "" -> fallback
      copy -> copy
    end
  end

  defp sanitize_room_copy(_value, fallback, _max_length), do: fallback

  defp choose_team(requested_team, members, team_size) do
    requested_team = normalize_team(requested_team)
    a_count = Enum.count(members, &(&1.team == :a))
    b_count = Enum.count(members, &(&1.team == :b))

    cond do
      requested_team == :a and a_count < team_size -> :a
      requested_team == :b and b_count < team_size -> :b
      a_count <= b_count and a_count < team_size -> :a
      b_count < team_size -> :b
      true -> Repo.rollback(:room_full)
    end
  end

  defp next_position(members, team, team_size) do
    occupied = members |> Enum.filter(&(&1.team == team)) |> Enum.map(& &1.position)
    Enum.find(1..team_size, &(&1 not in occupied))
  end

  defp normalize_team(:a), do: :a
  defp normalize_team("a"), do: :a
  defp normalize_team(:b), do: :b
  defp normalize_team("b"), do: :b
  defp normalize_team(_team), do: nil

  defp opposite_team(:a), do: :b
  defp opposite_team(:b), do: :a

  defp match_id(%Match{id: id}), do: id
  defp match_id(id) when is_binary(id), do: id

  defp normalize_room_code(code), do: code |> String.trim() |> String.upcase()

  defp new_room_code do
    :crypto.strong_rand_bytes(5) |> Base.encode32(case: :upper, padding: false)
  end

  defp new_seed, do: System.unique_integer([:positive, :monotonic])

  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _invalid -> default
    end
  end

  defp normalize_integer(_value, default), do: default

  defp arena_grimoire?(%Grimoire{metadata: metadata}) when is_map(metadata),
    do: metadata["arena"] == true

  defp arena_grimoire?(_grimoire), do: false

  defp grimoire_has_spells?(grimoire_id) do
    Repo.exists?(from entry in GrimoireEntry, where: entry.grimoire_id == ^grimoire_id)
  end

  defp inactive_status(%Grimoire{status: :active}), do: :sealed
  defp inactive_status(%Grimoire{status: status}), do: status

  defp ensure_arena_character!(character) do
    if CharacterProfiles.arena?(character),
      do: :ok,
      else: Repo.rollback(profile_error(:character_id, "is not an arena character"))
  end

  defp preload_profile(nil), do: nil
  defp preload_profile(profile), do: Repo.preload(profile, [:account, :character])

  defp preload_match(nil), do: nil

  defp preload_match(match) do
    Repo.preload(
      match,
      [
        :realm,
        :host_profile,
        combat: [participants: [:character, grimoire: :entries]],
        members: [profile: :character]
      ],
      force: true
    )
  end

  defp profile_error(field, message) do
    %Profile{} |> Changeset.change() |> Changeset.add_error(field, message)
  end

  defp match_error(field, message) do
    %Match{} |> Changeset.change() |> Changeset.add_error(field, message)
  end

  defp grimoire_error(field, message) do
    %Grimoire{} |> Changeset.change() |> Changeset.add_error(field, message)
  end

  defp insert_or_rollback(changeset) do
    case Repo.insert(changeset) do
      {:ok, struct} -> struct
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp broadcast_match_result({:ok, %Match{} = match} = result, event) do
    Phoenix.PubSub.broadcast(MMGO.PubSub, room_topic(match.id), {event, match})
    Phoenix.PubSub.broadcast(MMGO.PubSub, queue_topic(match.host_profile.season), {event, match})

    Enum.each(match.members, fn member ->
      Phoenix.PubSub.broadcast(MMGO.PubSub, profile_topic(member.profile_id), {event, match})
    end)

    result
  end

  defp broadcast_match_result(result, _event), do: result

  defp broadcast_profile_result({:ok, result} = transaction_result, profile_id, event) do
    Phoenix.PubSub.broadcast(MMGO.PubSub, profile_topic(profile_id), {event, result})
    transaction_result
  end

  defp broadcast_profile_result(result, _profile_id, _event), do: result

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_keys(value)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(value), do: value
end
