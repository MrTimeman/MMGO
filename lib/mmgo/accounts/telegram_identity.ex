defmodule MMGO.Accounts.TelegramIdentity do
  use Ecto.Schema

  import Ecto.Changeset

  alias MMGO.Accounts.Account

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "telegram_identities" do
    field :telegram_user_id, :integer
    field :telegram_username, :string
    field :first_name, :string
    field :last_name, :string
    field :language_code, :string
    field :is_bot, :boolean, default: false
    field :auth_data, :map, default: %{}
    field :last_seen_at, :utc_datetime_usec

    belongs_to :account, Account

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [
      :telegram_user_id, :telegram_username, :first_name, :last_name,
      :language_code, :is_bot, :auth_data, :last_seen_at
    ])
    |> validate_required([:telegram_user_id, :last_seen_at])
    |> unique_constraint(:telegram_user_id)
    |> unique_constraint(:account_id)
  end
end
