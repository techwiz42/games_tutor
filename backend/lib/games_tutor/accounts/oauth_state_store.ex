defmodule GamesTutor.Accounts.OAuthStateStore do
  @moduledoc """
  Ephemeral CSRF state-token store for the Google OAuth flow, backed by ETS.
  Single-node only -- fine for a single BEAM node (unlike the equivalent
  in-memory set in the prior Python/multi-worker backend, one BEAM node
  already handles high concurrency in-process), but would need to move to a
  shared store (e.g. a DB table or Redis) if this ever runs as a multi-node
  cluster.
  """
  use GenServer

  @table :oauth_states
  # 10 minutes -- generous for completing a Google login redirect.
  @ttl_seconds 600

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def put(state) do
    :ets.insert(@table, {state, System.system_time(:second) + @ttl_seconds})
    :ok
  end

  @doc "Returns true and consumes the state (single-use) if valid; false otherwise."
  def consume(state) do
    case :ets.take(@table, state) do
      [{^state, expires_at}] -> expires_at > System.system_time(:second)
      [] -> false
    end
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:set, :public, :named_table])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:second)
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, 60_000)
end
