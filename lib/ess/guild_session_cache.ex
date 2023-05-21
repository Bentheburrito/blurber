defmodule Blurber.ESS.GuildSessionCache do
  use Agent

  def start_link(_) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def put(guild_id, pid) do
    Agent.update(__MODULE__, &Map.put(&1, guild_id, pid))
  end

  def fetch(guild_id) do
    Agent.get(__MODULE__, &Map.fetch(&1, guild_id))
  end

  def delete(guild_id) do
    Agent.update(__MODULE__, &Map.delete(&1, guild_id))
  end
end
