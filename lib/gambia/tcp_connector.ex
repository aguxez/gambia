defmodule Gambia.TCPConnetor do
  @moduledoc false

  use GenServer

  require Logger

  alias Gambia.Message
  alias Gambia.Schema.Peer

  # Only waits this amount of time trying a connection to a peer
  @connect_timeout 500

  def start_link(_args) do
    state = %{connected_peers: %{}, info_hash: nil}
    GenServer.start_link(__MODULE__, state, name: :tcp_connector)
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_info({:try_connect_to_peer, udp_connector_state}, state) do
    # Tracker is a map with information from the tracker, on those we will find the peers list

    # ! Process.send(self(), {:do_handshake_to_peers, udp_connector_state}, [:nosuspend])
    {:noreply,
     %{
       state
       | connected_peers: connect_to_peers(udp_connector_state),
         info_hash: udp_connector_state.magnet.info_hash
     }}
  end

  @impl true
  def handle_info({:tcp_closed, closed_socket}, state) do
    new_state = Map.delete(state.connected_peers, closed_socket)

    Logger.warn("Client #{inspect(closed_socket)} closed the connection...")

    {:noreply, %{state | connected_peers: new_state}}
  end

  @impl true
  def handle_info({:tcp, socket, message}, state) do
    new_state = tcp_handle_message(message, socket, state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.error("UNHANDLED MESSAGE ON TCP - #{inspect(message)}")

    {:noreply, state}
  end

  # This is a handshake, we need to verify the info_hash we receive is the same we have saved
  defp tcp_handle_message(
         <<19, "BitTorrent protocol", _reserved::64, int_hash::160, _::binary>>,
         socket,
         state
       ) do
    Logger.info("Confirming handshake with #{inspect(socket)}")

    # If our hash does not match what the peer sent back we're going to close the connection
    connected_peers =
      if state.info_hash == <<int_hash::160>> do
        :gen_tcp.send(socket, Message.interested())

        state.connected_peers
      else
        :gen_tcp.close(socket)

        Logger.info("Closed connection with #{inspect(socket)}")

        #  Drop socket from state
        Map.delete(state.connected_peers, socket)
      end

    %{state | connected_peers: connected_peers}
  end

  defp tcp_handle_message(<<0, 0, 0, 0>>, socket, state) do
    Logger.info("keep_alive received from #{inspect(socket)}")

    :gen_tcp.send(socket, Message.keep_alive())

    state
  end

  defp tcp_handle_message(<<0::24, 1, 0>>, socket, state) do
    Logger.info("Received choke from #{inspect(socket)}")

    # Close the connection and remove from state
    :gen_tcp.close(socket)

    connected_peers = Map.delete(state.connected_peers, socket)

    %{state | connected_peers: connected_peers}
  end

  defp tcp_handle_message(<<0::24, 1, 1>>, socket, state) do
    Logger.info("Received unchoke from #{inspect(socket)}")

    put_in_peer_state(state, socket, &conn_state_peer_update(&1, socket, "unchoked"))
  end

  defp tcp_handle_message(<<0::24, 1, 2>>, socket, state) do
    Logger.info("Received interested from #{inspect(socket)}")

    put_in_peer_state(state, socket, &conn_state_peer_update(&1, socket, "interested"))
  end

  defp tcp_handle_message(<<0::24, 1, 3>>, socket, state) do
    Logger.info("Received uninterested from #{inspect(socket)}")

    put_in_peer_state(state, socket, &conn_state_peer_update(&1, socket, "uninterested"))
  end

  defp tcp_handle_message(<<_::32, _::8, _::binary>> = message, socket, state) do
    case Message.Handler.handle(message, socket, state) do
      {new_state, <<0>>} ->
        new_state

      {new_state, response} ->
        :gen_tcp.send(socket, response)

        new_state
    end
  end

  defp tcp_handle_message(message, socket, state) do
    Logger.error("Unhandled message #{inspect(message)} from #{inspect(socket)}")

    state
  end

  # TODO: Improve these two functions, we're unnecesarily accessing and updating the state
  defp put_in_peer_state(state, socket, function) do
    # Check if socket is on state and update state with function
    if get_in(state, [:connected_peers, socket]) do
      function.(state)
    else
      state
    end
  end

  defp conn_state_peer_update(state, socket, status) do
    case get_in(state, [:connected_peers, socket]) do
      nil ->
        nil

      peer ->
        changeset = Peer.changeset(peer, %{conn_state: status})

        update_in(state, [:connected_peers, socket], &Map.merge(&1, changeset.changes))
    end
  end

  defp connect_to_peers(udp_state) do
    # |> Task.async_stream(&try_peer(&1, udp_state), max_concurrency: 1)
    # |> Enum.into([], fn {:ok, res} -> res end)
    udp_state.announced_resp.peers
    |> Enum.map(&try_peer(&1, udp_state))
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end

  defp try_peer(peer, udp_state) do
    #  This tries to connect to the peer and send the handshake message at the same time
    #  then we will save the connected peers into state
    with {:ok, socket} <- :gen_tcp.connect(peer.ip, peer.port, [:binary], @connect_timeout),
         :ok <- :gen_tcp.send(socket, Message.handshake(udp_state.magnet.info_hash)) do
      Logger.info("Sent handshake message to #{inspect(peer.ip)}")

      {socket, struct(Peer)}
    else
      {:error, :timeout} ->
        Logger.warn("Tried to connect to #{inspect(peer.ip)} but it timed-out")
        nil

      {:error, :econnrefused} ->
        Logger.warn("Peer #{inspect(peer.ip)} refused connection...")
        nil

      error ->
        Logger.error("Received unhandled error on TCP conn - #{inspect(error)}")
        nil
    end
  end
end
