defmodule Blurber.ESS.Session do
  @enforce_keys [:voicepack, :guild_id]
  defstruct killing_spree_count: 0,
            last_kill_timestamp: 0,
            voicepack: nil,
            guild_id: nil
end
