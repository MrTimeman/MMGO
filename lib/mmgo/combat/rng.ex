defmodule MMGO.Combat.RNG do
  def percent(seed, components) do
    :erlang.phash2({seed, components}, 100) + 1
  end

  def bounded_noise(_seed, _components, 0), do: 0

  def bounded_noise(seed, components, variance) when variance > 0 do
    :erlang.phash2({seed, components}, variance * 2 + 1) - variance
  end

  def order_key(seed, components) do
    :erlang.phash2({seed, components})
  end
end
