defmodule Gambia.TCPConnetor do
  @moduledoc false

  use GenServer

  require Logger

  alias Gambia.Utils

  # Only waits 2 seconds trying a connection to a peer
  @connect_timeout 500

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: :tcp_connector)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_info({:try_connect_to_peer, udp_connector_state}, _state) do
    # Tracker is a map with information from the tracker, on those we will find the peers list
    Process.send(self(), {:do_handshake_to_peers, udp_connector_state}, [:nosuspend])
    {:noreply, connect_to_peers(udp_connector_state)}
  end

  @impl true
  def handle_info({:tcp_closed, port}, state) do
    closed_client = Enum.find(state.connected_peers, &(&1.port == port))
    new_state = List.delete(state.connected_peers, &(&1.port == port))

    unless is_nil(closed_client) do
      Logger.info("Client #{inspect(closed_client.ip)} closed the connection...")
    end

    {:noreply, %{state | connected_peers: new_state}}
  end

  @impl true
  def handle_info({:do_handshake_to_peers, udp_state}, state) do
    Logger.info("Trying handshake with peers...")

    peer = Enum.random(state.connected_peers)

    :gen_tcp.send(peer.socket, build_handhsake_msg(udp_state))

    {:noreply, state}
  end

  defp connect_to_peers(udp_state) do
    connected_peers = Enum.reduce(udp_state.announced_resp.peers, [], &try_peer/2)

    %{connected_peers: connected_peers}
  end

  defp try_peer(peer, connected_peers) do
    case :gen_tcp.connect(peer.ip, peer.port, [:binary], @connect_timeout) do
      {:ok, socket} ->
        Logger.info("Connected to #{inspect(peer.ip)}")

        peer_state = Map.put(peer, :socket, socket)
        [peer_state | connected_peers]

      {:error, :timeout} ->
        Logger.info("Tried to connect to #{inspect(peer.ip)} but it timed-out")
        connected_peers

      error ->
        Logger.error("Received unhandled error on TCP conn - #{inspect(error)}")
        connected_peers
    end
  end

  defp build_handhsake_msg(udp_state) do
    # See https://wiki.theory.org/index.php/BitTorrentSpecification#Handshake
    # At this point magnet's info hash has been parsed already from the UDP caller

    <<19, "BitTorrent protocol">> <>
      <<0::64>> <>
      udp_state.magnet.info_hash <>
      Utils.get_peer_id()
  end
end
