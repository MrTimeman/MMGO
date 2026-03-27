defmodule MMGO.AI.Provider do
  @callback compile_spell(map(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback narrate_turn(map(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
