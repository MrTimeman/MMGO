defmodule MMGO.Telegram.ReleaseChannel do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "telegram_release_channels" do
    field :key, :string
    field :chat_id, :integer
    field :chat_title, :string
    field :configured_by_telegram_user_id, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:key, :chat_id, :chat_title, :configured_by_telegram_user_id])
    |> validate_required([:key, :chat_id, :configured_by_telegram_user_id])
    |> validate_length(:key, min: 3, max: 80)
    |> validate_length(:chat_title, max: 255)
    |> unique_constraint(:key)
  end
end
