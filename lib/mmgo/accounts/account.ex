defmodule MMGO.Accounts.Account do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.{Character, TelegramIdentity}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "accounts" do
    field :display_name, :string
    field :handle, :string
    field :status, Ecto.Enum, values: [:active, :suspended], default: :active
    field :settings, :map, default: %{}

    has_many :characters, Character
    has_one :telegram_identity, TelegramIdentity

    timestamps(type: :utc_datetime_usec)
  end

  def registration_changeset(account, attrs) do
    account
    |> cast(attrs, [:display_name, :handle, :settings])
    |> validate_required([:display_name, :handle])
    |> validate_length(:display_name, min: 2, max: 80)
    |> validate_length(:handle, min: 3, max: 64)
    |> validate_format(:handle, ~r/^[a-z0-9-]+$/)
    |> unique_constraint(:handle)
  end
end
