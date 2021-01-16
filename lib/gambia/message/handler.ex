defmodule Gambia.Message.Handler do
  @moduledoc """
  Provides functionality to act based on the type of message we're receiving.
  """

  alias Gambia.Message

  @messages_with_payload [3, 4, 5, 6, 7, 8]

  @spec handle(binary(), Port.t(), map()) :: {map(), binary()}
  def handle(<<_::32, msg_id::8, _::binary>> = message, socket, tcp_state) do
    with {true, current_peer_state} <- msg_completed?(message, socket, tcp_state),
         :bitfield <- identify(msg_id) do
      # current_peer_state is the last message (or payload) we processed for this peer.
      # it returns the current body of the message, so if it this is a bitfield it will be the
      # pieces this particular peer has of the file we're requesting and we can clean the last_message_state key
      # as all messages have been received
      new_peer_state =
        update_in(
          tcp_state,
          [:connected_peers, socket],
          &Map.merge(&1, %{last_message_state: nil, pieces: current_peer_state})
        )

      {new_peer_state, Message.interested()}
    else
      {false, :unknown} ->
        {tcp_state, <<0>>}

      {false, current_peer_state} ->
        new_peer_state =
          put_in(tcp_state, [:connected_peers, socket, :last_message_state], current_peer_state)

        {new_peer_state, <<0>>}

      whatever ->
        IO.inspect(whatever, label: "HANDLE")
        {tcp_state, <<0>>}
    end
  end

  #  This function checks whether or not the message is incomplete and we should wait before processing
  defp msg_completed?(<<msg_length::32, msg_id::8, payload::binary>> = message, socket, tcp_state) do
    current_peer_state =
      get_in(tcp_state, [:connected_peers, socket, :last_message_state]) || message

    IO.inspect({byte_size(current_peer_state), msg_length}, label: "HANDLING #{msg_id}")

    with {true, :known} <- {msg_id in @messages_with_payload, :known},
         true <- byte_size(current_peer_state) >= msg_length do
      {true, current_peer_state}
    else
      false -> {false, current_peer_state <> payload}
      {false, :known} -> {false, :unknown}
    end
  end

  defp identify(4), do: :have
  defp identify(5), do: :bitfield
  defp identify(6), do: :request
  defp identify(7), do: :piece
  defp identify(8), do: :cancel
  defp identify(msg_id), do: msg_id
end
