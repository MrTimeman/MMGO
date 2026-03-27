defmodule MMGO.Notifications.Notification do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Character

  @channels [:telegram]
  @statuses [:pending, :sent, :failed, :discarded]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notifications" do
    field :channel, Ecto.Enum, values: @channels
    field :kind, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :scheduled_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :payload, :map, default: %{}
    field :metadata, :map, default: %{}
    field :error, :string
    field :dedupe_key, :string

    belongs_to :character, Character

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :channel,
      :kind,
      :status,
      :scheduled_at,
      :delivered_at,
      :payload,
      :metadata,
      :error,
      :dedupe_key,
      :character_id
    ])
    |> validate_required([:channel, :kind, :status, :scheduled_at, :payload, :character_id])
    |> validate_length(:kind, min: 3, max: 120)
    |> validate_length(:dedupe_key, min: 3, max: 200)
    |> unique_constraint(:dedupe_key, name: :notifications_character_dedupe_key_index)
  end
end
