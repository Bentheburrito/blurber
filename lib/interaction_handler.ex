defmodule Blurber.InteractionHandler do
  alias Nostrum.Struct.Interaction
  alias Nostrum.Struct.ApplicationCommandInteractionData, as: InteractionData

  @type response_data_field ::
          :content
          | :embeds
          | :components

  def handle_interaction(%Interaction{data: %InteractionData{name: name}} = interaction)
      when not is_nil(name) do
    SlashCommand.handle_interaction(interaction)
  end

  def handle_interaction(
        %Interaction{data: %InteractionData{custom_id: _custom_id}} = interaction
      ) do
    Buttons.handle_interaction(interaction)
  end

  @spec respond(Interaction.t(), [{response_data_field | :callback, any()}], boolean()) ::
          {:ok} | {:error, any()}
  def respond(%Interaction{} = interaction, data, ephemeral \\ false) do
    data =
      data
      |> Keyword.take([:content, :embeds, :components, :allowed_mentions])
      |> Map.new()
      |> then(&if ephemeral, do: Map.put(&1, :flags, 64), else: &1)

    response = %{
      # ChannelMessageWithSource
      type: 4,
      data: data
    }

    Nostrum.Api.create_interaction_response(interaction, response)
  end
end
