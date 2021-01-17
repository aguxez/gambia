defmodule Gambia.Schema.Peer do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    # all connections start as 'choked'
    field(:conn_state, :string, default: "choked")
    field(:last_message_state, :binary)

    embeds_many(:pieces, __MODULE__.Piece)
  end

  def changeset(%__MODULE__{} = peer, params \\ %{}) do
    cast(peer, params, [:conn_state, :last_message_state])
  end
end
