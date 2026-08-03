defmodule MMGO.Telegram.ChangesetErrorsTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias MMGO.Telegram.ChangesetErrors

  test "translates standard Ecto validations and player-facing field labels" do
    changeset =
      {%{}, %{name: :string, quantity: :integer}}
      |> Changeset.cast(%{"quantity" => 0}, [:name, :quantity])
      |> Changeset.validate_required([:name])
      |> Changeset.validate_number(:quantity, greater_than: 0)

    rendered = ChangesetErrors.format(changeset)

    assert rendered =~ "Название: не заполнено"
    assert rendered =~ "Количество: должно быть больше 0"
    refute rendered =~ "can't be blank"
    refute rendered =~ "must be greater"
  end

  test "translates stable domain errors without changing their internal representation" do
    changeset =
      {%{}, %{status: :string}}
      |> Changeset.change()
      |> Changeset.add_error(:status, "character already has an active journey")

    assert changeset.errors == [
             status: {"character already has an active journey", []}
           ]

    assert ChangesetErrors.format(changeset) ==
             "Состояние: у персонажа уже есть активный путь"
  end

  test "unknown messages and fields use a Russian fallback and never expose raw details" do
    changeset =
      {%{}, %{upstream_payload: :string}}
      |> Changeset.change()
      |> Changeset.add_error(
        :upstream_payload,
        "upstream exploded with secret token SHOULD_NOT_LEAK"
      )

    rendered = ChangesetErrors.format(changeset)

    assert rendered == "Данные: данные не прошли проверку"
    refute rendered =~ "upstream"
    refute rendered =~ "SHOULD_NOT_LEAK"
    refute rendered =~ "upstream_payload"
  end

  test "an empty changeset still produces a useful Russian failure" do
    changeset = Changeset.change({%{}, %{}})

    assert ChangesetErrors.format(changeset) == "данные не прошли проверку"
  end
end
