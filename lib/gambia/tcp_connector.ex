defmodule Gambia.TCPConnetor do
  @moduledoc false

  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: :tcp_connector)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_info({:try_connect_to_peer, tracker}, state) do
    # Tracker is a map with information from the tracker, on those we will find the peers list

    IO.inspect(tracker)

    {:noreply, state}
  end
end
