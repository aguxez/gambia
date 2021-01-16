defmodule Gambia.Utils do
  @moduledoc false

  @spec get_peer_id() :: binary()
  def get_peer_id do
    String.pad_leading("-MD0001" <> :crypto.strong_rand_bytes(13), 13, "0")
  end

  @spec info_hash_from_magnet(Magnet.t()) :: binary()
  def info_hash_from_magnet(%Magnet{} = magnet) do
    magnet.info_hash
    |> hd()
    |> String.split(":")
    |> Enum.at(-1)
    |> String.upcase()
    |> Base.decode16!()
  end
end
