defmodule MMGO.Actors do
  import Ecto.Query, warn: false

  alias MMGO.Actors.ActorTemplate
  alias MMGO.Dungeons.Encounter
  alias MMGO.Dungeons.EncounterSpawn
  alias MMGO.Repo
  alias MMGO.Worlds.Realm

  def list_actor_templates(realm_id) when is_binary(realm_id) do
    Repo.all(
      from actor_template in ActorTemplate,
        where: actor_template.realm_id == ^realm_id,
        order_by: [asc: actor_template.inserted_at]
    )
  end

  def get_actor_template!(id), do: Repo.get!(ActorTemplate, id)

  def get_actor_template_by_code(realm_id, code)
      when is_binary(realm_id) and is_binary(code) do
    Repo.get_by(ActorTemplate, realm_id: realm_id, code: code)
  end

  def create_actor_template(%Realm{} = realm, attrs \\ %{}) do
    attrs = Map.put(stringify_keys(attrs), "realm_id", realm.id)

    %ActorTemplate{}
    |> ActorTemplate.changeset(attrs)
    |> Repo.insert()
  end

  def ensure_generic_template(%Realm{} = realm, encounter_kind, threat_level) do
    code = "generic-#{encounter_kind}-#{threat_level}"

    case get_actor_template_by_code(realm.id, code) do
      %ActorTemplate{} = actor_template ->
        {:ok, actor_template}

      nil ->
        create_actor_template(realm, %{
          code: code,
          name: generic_name(encounter_kind, threat_level),
          role: :hostile,
          combat_level: max(div(threat_level, 5), 1),
          base_hp: max(threat_level * 6, 15),
          behavior_profile: :aggressive,
          metadata: %{"generated" => true, "encounter_kind" => encounter_kind}
        })
    end
  end

  def list_encounter_spawns(encounter_id) when is_binary(encounter_id) do
    Repo.all(
      from encounter_spawn in EncounterSpawn,
        where: encounter_spawn.encounter_id == ^encounter_id,
        order_by: [asc: encounter_spawn.inserted_at],
        preload: [:actor_template]
    )
  end

  def get_encounter_spawn!(id) do
    EncounterSpawn
    |> Repo.get!(id)
    |> Repo.preload(:actor_template)
  end

  def create_encounter_spawn(
        %Encounter{} = encounter,
        %ActorTemplate{} = actor_template,
        attrs \\ %{}
      ) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("encounter_id", encounter.id)
      |> Map.put("actor_template_id", actor_template.id)

    %EncounterSpawn{}
    |> EncounterSpawn.changeset(attrs)
    |> Repo.insert()
  end

  def ensure_default_spawns(%Encounter{} = encounter, %Realm{} = realm) do
    case list_encounter_spawns(encounter.id) do
      [] ->
        with {:ok, actor_template} <-
               ensure_generic_template(realm, encounter.encounter_kind, encounter.threat_level),
             {:ok, encounter_spawn} <-
               create_encounter_spawn(encounter, actor_template, %{
                 quantity: spawn_quantity(encounter.threat_level),
                 status: :active,
                 current_hp: actor_template.base_hp,
                 metadata: %{}
               }) do
          {:ok, [Repo.preload(encounter_spawn, :actor_template)]}
        end

      spawns ->
        {:ok, spawns}
    end
  end

  defp spawn_quantity(threat_level) when threat_level >= 60, do: 3
  defp spawn_quantity(threat_level) when threat_level >= 25, do: 2
  defp spawn_quantity(_threat_level), do: 1

  defp generic_name("boss", _threat_level), do: "Dungeon Boss"
  defp generic_name("hazard", _threat_level), do: "Dungeon Hazard"
  defp generic_name(_kind, threat_level), do: "Dungeon Foe #{threat_level}"

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
