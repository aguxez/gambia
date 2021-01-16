defmodule Gambia.UdpConnector do
  @moduledoc false

  use GenServer

  require Logger

  alias Gambia.Utils

  @port 8080

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: :udp_connector)
  end

  @impl true
  def init(state) do
    :timer.send_interval(10_000, self(), :check_tracker_connection)

    {:ok, state, {:continue, :trackers_fetching}}
  end

  @impl true
  def handle_continue(:trackers_fetching, _state) do
    magnet = parse_magnet_link()

    {:ok, socket} = :gen_udp.open(@port)
    Process.send(self(), :init_connect, [:nosuspend])

    {:noreply, %{trackers: magnet.announce, socket: socket, magnet: magnet}}
  end

  @impl true
  def handle_info(:check_tracker_connection, state) do
    # sometimes we do not receive any response from a tracker, what we do on this check is
    # check for a populated state, in case there's nothing we will close the socket
    # so we don't receive messages from the old socket (in case of delays) and start a new connection
    # for the saved trackers
    new_state =
      if Map.has_key?(state, :announced_resp) do
        # Having this key on state means we already picked a tracker to work with
        state
      else
        Logger.info("Trying to reconnect to another tracker...")
        :gen_udp.close(state.socket)

        {:ok, socket} = :gen_udp.open(@port)

        Process.send(self(), :init_connect, [:nosuspend])
        %{state | socket: socket}
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:init_connect, state) do
    # We're going to try each tracker and the one that returns peers is the one we're going to stay with
    {tried_tracker, remaining_trackers, tracker_ip} = try_trackers(state.trackers, state.socket)

    {:noreply,
     Map.merge(state, %{host: tried_tracker, trackers: remaining_trackers, tracker_ip: tracker_ip})}
  end

  @impl true
  def handle_info(
        {:udp, _socket, _ip, _port, msg},
        state
      ) do
    list_msg = :binary.list_to_bin(msg)
    msg_action = get_action(list_msg)

    case msg_action do
      0 -> Process.send(self(), {:connect_resp, list_msg}, [:nosuspend])
      1 -> Process.send(self(), {:announce_resp, list_msg}, [:nosuspend])
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:connect_resp, message}, state) do
    <<_::32, _::32, conn_id::binary>> = message
    port = state.host.port

    announce_msg =
      conn_id <>
        <<1::32>> <>
        :crypto.strong_rand_bytes(4) <>
        state.magnet.info_hash <>
        Utils.get_peer_id() <>
        <<0::64>> <>
        <<8_978_640_732::64>> <>
        <<0::64>> <>
        <<0::32>> <>
        <<0::32>> <>
        <<0::32>> <>
        <<-1::32>> <>
        <<port::16>>

    :gen_udp.send(state.socket, state.tracker_ip, state.host.port, announce_msg)

    {:noreply, state}
  end

  @impl true
  def handle_info({:announce_resp, message}, state) do
    parsed_resp = parse_announce_resp(message)

    new_state =
      if length(parsed_resp.peers) >= 2 do
        new_state = Map.put(state, :announced_resp, parsed_resp)

        Process.send(:tcp_connector, {:try_connect_to_peer, new_state}, [:nosuspend])

        new_state
      else
        Process.send(self(), :init_connect, [:nosuspend])

        state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.info("Unhandled message on UDP connector - #{inspect(msg)}")

    {:noreply, state}
  end

  defp parse_magnet_link(file \\ "bunny.torrent") do
    magnet =
      file
      |> File.read!()
      |> Magnet.decode()
      |> Enum.into(%Magnet{})

    %{magnet | info_hash: Utils.info_hash_from_magnet(magnet)}
  end

  defp try_trackers([], _socket) do
    {nil, [], {}}
  end

  defp try_trackers([tracker | rest], socket) do
    Logger.info("Trying to connect to #{tracker}")

    parsed_host = URI.parse(tracker)

    {:ok, host_ip} =
      parsed_host.host
      |> :binary.bin_to_list()
      |> :inet.getaddr(:inet)

    message = <<0x41727101980::64>> <> <<0::32>> <> :crypto.strong_rand_bytes(4)

    :gen_udp.send(socket, host_ip, parsed_host.port, message)

    {parsed_host, rest, host_ip}
  end

  defp parse_announce_resp(message) do
    <<action::32, tx_id::32, interval::32, leechers::32, seeders::32, rest_for_peers::binary>> =
      message

    %{
      action: action,
      transaction_id: tx_id,
      interval: interval,
      leechers: leechers,
      seeders: seeders,
      peers: parse_peers(rest_for_peers)
    }
  end

  defp parse_peers(peers) do
    peers
    |> :binary.bin_to_list()
    |> Enum.chunk_every(6)
    |> Enum.map(fn peer ->
      <<ip::32, port::16>> = :binary.list_to_bin(peer)

      %{
        ip: parse_ip(ip),
        port: port
      }
    end)
  end

  defp parse_ip(ip) do
    # We do this for compatibility with the :gen_tcp module
    ip
    |> :binary.encode_unsigned()
    |> :binary.bin_to_list()
    |> Enum.reduce({}, fn ip_part, tuple -> Tuple.append(tuple, ip_part) end)
  end

  defp get_action(message) do
    <<action::32, _::binary>> = message

    action
  end
end
