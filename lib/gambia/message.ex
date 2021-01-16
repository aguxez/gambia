defmodule Gambia.Message do
  @moduledoc """
  Provides convenient functions to build messages to send to peers
  """

  alias Gambia.Utils

  @spec handshake(String.t()) :: binary()
  def handshake(info_hash) do
    # See https://wiki.theory.org/index.php/BitTorrentSpecification#Handshake
    # At this point magnet's info hash has been parsed already from the UDP caller

    <<19, "BitTorrent protocol", 0::64>> <>
      info_hash <>
      Utils.get_peer_id()
  end

  @spec get_length(binary()) :: pos_integer()
  def get_length(message) do
    <<msg_length::32-big, _::binary>> = message
    msg_length + 4
  end

  @spec keep_alive :: binary()
  def keep_alive, do: <<0::32>>

  @spec choke :: binary()
  def choke, do: <<0::24, 1>>

  @spec unchoke :: binary()
  def unchoke, do: <<0::24, 1, 1>>

  @spec interested :: binary()
  def interested, do: <<0::24, 1, 2>>

  @spec uninterested :: binary()
  def uninterested, do: <<0::24, 1, 3>>
end
