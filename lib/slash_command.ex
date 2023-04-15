defmodule SlashCommand do
  @moduledoc """
  A behaviour for defining Slash Commands.
  """

  use Agent

  require Logger

  alias Nostrum.Api
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.ApplicationCommandInteractionData, as: InteractionData
  alias Blurber.InteractionHandler

  @callback command_definition() :: map()
  @callback command_scope() ::
              :global
              | {:guild, guild_id :: Nostrum.Snowflake.t() | [Nostrum.Snowflake.t()]}
  @callback run(Interaction.t()) ::
              {:raw_response, map()}
              | {:response, Keyword.t()}
  @callback ephemeral?() :: boolean()
  @optional_callbacks ephemeral?: 0

  @unknown_command_error_message "Oops! I don't actually recognize that command. The developer has been notified and will address this if it's an issue"
  @unknown_command_error_notif 254_728_052_070_678_529

  def start_link(_init_args) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  ### Public
  def get(command_name) do
    Agent.get(__MODULE__, &Map.get(&1, command_name, :notacommand))
  end

  def put(command_module) do
    %{name: command_name} = apply(command_module, :command_definition, [])
    Agent.update(__MODULE__, &Map.put(&1, command_name, {command_module, nil}))
  end

  def put_register(command_name, reg_ack) do
    Agent.update(
      __MODULE__,
      &Map.update!(&1, command_name, fn {command_module, _} -> {command_module, reg_ack} end)
    )
  end

  def delete(command_name) do
    {module, reg_ack} = Agent.get_and_update(__MODULE__, &Map.pop(&1, command_name))
    unregister_command(module, reg_ack)
  end

  def list do
    Agent.get(__MODULE__, & &1)
  end

  @spec get_options(Interaction.t()) :: %{String.t() => integer() | String.t()}
  def get_options(%Interaction{
        data: %Nostrum.Struct.ApplicationCommandInteractionData{options: nil}
      }) do
    %{}
  end

  def get_options(%Interaction{data: data}) when not is_map_key(data, :options), do: %{}

  def get_options(%Interaction{data: data}) do
    names = Enum.map(data.options, fn opt -> opt.name end)

    values =
      Stream.map(data.options, fn opt -> opt.value end)
      |> Enum.map(fn
        val when is_binary(val) ->
          case Integer.parse(val) do
            {num, _} -> num
            :error -> val
          end

        val ->
          val
      end)

    Enum.zip(names, values) |> Map.new()
  end

  def handle_interaction(%Interaction{data: %InteractionData{name: name}} = interaction) do
    with {module, _reg_ack} <- get(name),
         {:response, options} when is_list(options) <- apply(module, :run, [interaction]) do
      ephemeral =
        if function_exported?(module, :ephemeral?, 0) do
          apply(module, :ephemeral?, [])
        else
          false
        end

      InteractionHandler.respond(interaction, options, ephemeral)
    else
      {:raw_response, res} when is_map(res) ->
        Api.create_interaction_response(interaction, res)

      :notacommand ->
        Logger.error(
          "INTERACTION RECEIVED FOR UNKNOWN COMMAND: #{name} | interaction: #{inspect(interaction)}"
        )

        dm_channel = Api.create_dm!(@unknown_command_error_notif)

        Api.create_message(
          dm_channel.id,
          "INTERACTION RECEIVED FOR UNKNOWN COMMAND: #{name} | interaction: #{inspect(interaction)}"
        )

        InteractionHandler.respond(interaction, @unknown_command_error_message, true)
    end
  end

  def init_commands() do
    commands =
      with [guild_id | _rest] <- Application.get_env(:blurber, :guilds, []),
           {:ok, command_list} <- Api.get_guild_application_commands(guild_id) do
        Enum.map(command_list, fn command_reg ->
          {:ok, command_name} = Map.fetch(command_reg, :name)
          {command_name, command_reg}
        end)
        |> Enum.into(%{})
      end

    with {:ok, list} <- :application.get_key(:blurber, :modules) do
      list
      |> Enum.filter(&match?(["SlashCommand", _command], Module.split(&1)))
      |> then(fn modules ->
        Enum.each(modules, &put/1)
        modules
      end)
      |> filter_by_local_updates(commands)
      |> Enum.each(&register_command/1)
    end
  end

  defp filter_by_local_updates(slash_command_modules, registered_commands) do
    Enum.filter(slash_command_modules, fn module ->
      local_command = apply(module, :command_definition, [])
      name = local_command.name
      description = local_command.description
      reg_command = Map.get(registered_commands, name)

      if is_map_key(local_command, :options) do
        options = local_command.options
        not match?(%{name: ^name, description: ^description, options: ^options}, reg_command)
      else
        not match?(%{name: ^name, description: ^description}, reg_command)
      end
    end)
  end

  ### Impl
  defp register_command(command_module) do
    definition = apply(command_module, :command_definition, [])
    scope = apply(command_module, :command_scope, [])

    case scope do
      :global ->
        Api.create_global_application_command(definition)

      {:guild, guild_ids} when is_list(guild_ids) ->
        Enum.map(guild_ids, &Api.create_guild_application_command(&1, definition))

      {:guild, guild_id} ->
        Api.create_guild_application_command(guild_id, definition)
    end
  end

  defp unregister_command(command_module, command_reg_ack) do
    scope = apply(command_module, :command_scope, [])

    case scope do
      :global ->
        Api.delete_global_application_command(command_reg_ack.id)

      {:guild, guild_ids} when is_list(guild_ids) ->
        Enum.each(guild_ids, &Api.delete_guild_application_command(&1, command_reg_ack.id))

      {:guild, guild_id} ->
        Api.delete_guild_application_command(guild_id, command_reg_ack.id)
    end
  end
end
