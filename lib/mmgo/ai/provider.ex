defmodule MMGO.AI.Provider do
  @moduledoc """
  Behaviour implemented by AI providers (DeepSeek, Gemini, Mock, ...).

  Callbacks are capability-shaped rather than use-case-shaped: any new AI
  feature (spell compilation, exam grading, NPC dialogue, ...) is expressed
  as either a `structured_completion/3` (schema-validated JSON output) or a
  `text_completion/2` (free-form text) call, instead of requiring a new
  callback per feature.
  """

  @type prompt_payload :: %{system_prompt: String.t(), user_prompt: String.t()}
  @type schema :: map()

  @doc """
  Requests schema-validated JSON output from the provider.

  `schema` is a provider-neutral JSON Schema describing the desired output
  shape. How a provider fulfils that contract (native structured-output
  support, or injecting the schema into the prompt) is an internal detail of
  the provider implementation.
  """
  @callback structured_completion(prompt_payload(), schema(), keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Requests free-form text output from the provider.
  """
  @callback text_completion(prompt_payload(), keyword()) ::
              {:ok, String.t()} | {:error, term()}
end
