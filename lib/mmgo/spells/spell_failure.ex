defmodule MMGO.Spells.SpellFailure do
  @enforce_keys [:reason, :formula, :school]
  defstruct [
    :reason,
    :formula,
    :school,
    :ai_request,
    instability_markers: [],
    details: %{}
  ]
end
