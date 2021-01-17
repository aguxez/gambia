defmodule Gambia.Schema.Peer.Piece do
  @moduledoc """
  Handles state of a piece in a Peer
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field(:index, :integer)
    field(:has?, :boolean)
  end

  def changeset(%__MODULE__{} = piece, params \\ %{}) do
    piece
    |> cast(params, [:index, :has?])
    |> validate_required([:index, :has?])
  end
end
