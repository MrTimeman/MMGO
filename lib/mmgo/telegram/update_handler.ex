defmodule MMGO.Telegram.UpdateHandler do
  alias MMGO.Accounts

  def handle(%{"message" => %{"from" => from}, "update_id" => update_id}) do
    with {:ok, %{account: account, character: character}} <-
           Accounts.provision_from_telegram(from) do
      {:ok,
       %{
         handled: true,
         update_id: update_id,
         account_id: account.id,
         character_id: character && character.id,
         type: "message"
       }}
    end
  end

  def handle(%{"callback_query" => %{"from" => from}, "update_id" => update_id}) do
    with {:ok, %{account: account, character: character}} <-
           Accounts.provision_from_telegram(from) do
      {:ok,
       %{
         handled: true,
         update_id: update_id,
         account_id: account.id,
         character_id: character && character.id,
         type: "callback_query"
       }}
    end
  end

  def handle(%{"update_id" => update_id}) do
    {:ok, %{handled: false, update_id: update_id, reason: :unsupported_update}}
  end

  def handle(_update), do: {:error, :invalid_update}
end
