defmodule MMGO.CombatPlaytest do
  @moduledoc """
  Temporary switches for combat and spell-school playtests.

  The unrestricted mode deliberately lives behind one runtime flag so it can
  be removed or disabled without reconstructing Academy, location, and wager
  rules across several contexts.
  """

  def unrestricted? do
    Application.get_env(:mmgo, __MODULE__, [])[:unrestricted?] == true
  end
end
