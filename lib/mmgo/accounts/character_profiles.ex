defmodule MMGO.Accounts.CharacterProfiles do
  @moduledoc """
  Server-owned policies attached to one character rather than their account.
  """

  alias MMGO.Accounts.Character

  def sealed_spirit?(%Character{} = character),
    do: metadata_value(character, "profile_kind") == "sealed_spirit"

  def sealed_spirit?(_character), do: false

  def hidden_presence?(%Character{} = character),
    do: sealed_spirit?(character) or metadata_value(character, "hidden_presence") == true

  def hidden_presence?(_character), do: false

  def legendary_progression?(%Character{} = character),
    do: metadata_value(character, "progression_tier") == "legendary"

  def legendary_progression?(_character), do: false

  def mastered_track?(%Character{} = character, track) when is_atom(track),
    do: mastered_track?(character, Atom.to_string(track))

  def mastered_track?(%Character{} = character, track) when is_binary(track) do
    legendary_progression?(character) and
      track in List.wrap(metadata_value(character, "mastered_tracks"))
  end

  def mastered_track?(_character, _track), do: false

  def school_unlocked?(%Character{} = character, school) when is_atom(school),
    do: school_unlocked?(character, Atom.to_string(school))

  def school_unlocked?(%Character{} = character, school) when is_binary(school),
    do: school in List.wrap(metadata_value(character, "unlocked_schools"))

  def school_unlocked?(_character, _school), do: false

  def sealed_anchor_location_id(%Character{} = character),
    do: metadata_value(character, "sealed_anchor_location_id")

  def sealed_anchor_location_id(_character), do: nil

  defp metadata_value(%Character{metadata: metadata}, key) when is_map(metadata),
    do: Map.get(metadata, key)

  defp metadata_value(_character, _key), do: nil
end
