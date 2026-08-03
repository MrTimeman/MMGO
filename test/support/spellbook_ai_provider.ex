defmodule MMGO.TestSpellbookAIProvider do
  @moduledoc false

  @behaviour MMGO.AI.Provider

  def structured_completion(_prompt_payload, _schema, _opts) do
    Application.fetch_env!(:mmgo, __MODULE__)
  end

  def text_completion(_prompt_payload, _opts), do: {:ok, "unused"}
end
