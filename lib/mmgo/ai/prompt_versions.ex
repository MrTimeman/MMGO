defmodule MMGO.AI.PromptVersions do
  def for!(kind) do
    Application.fetch_env!(:mmgo, MMGO.AI)[:prompt_versions][kind]
  end
end
