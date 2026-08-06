defmodule GamesTutor.RateLimit do
  @moduledoc """
  Generic Redis-backed rate limiter -- a fixed window via INCR+EXPIRE, the
  same simple pattern already proven for voice session starts (see
  `GamesTutor.Voice`), generalized so auth and engine-cost endpoints can
  use it too. Not a true sliding window (a burst right at a window
  boundary can allow up to ~2x the nominal rate over the boundary), but
  simple, fast, and good enough for abuse-prevention rather than precise
  quota enforcement.
  """

  @doc "Returns :ok or {:error, :rate_limited}."
  def check(key, max, window_seconds) do
    {:ok, count} = Redix.command(GamesTutor.Redis, ["INCR", key])
    if count == 1, do: Redix.command(GamesTutor.Redis, ["EXPIRE", key, to_string(window_seconds)])

    if count > max, do: {:error, :rate_limited}, else: :ok
  end
end
