defmodule Blurber do
  alias Nostrum.Struct.Interaction

  def query_weapon_ids do
    HTTPoison.get!(
      "https://census.lithafalcon.cc/get/ps2/item?code_factory_name=Weapon&c:show=item_id&c:limit=5000"
    ).body
    |> Jason.decode!()
    |> Map.fetch!("item_list")
    |> Enum.map(fn item -> item["item_id"] end)
  end

  def service_id do
    System.get_env("SERVICE_ID")
  end

  def get_options(%Interaction{data: data}) when not is_map_key(data, :options), do: %{}

  def get_options(%Interaction{data: data}) do
    names = Enum.map(data.options, fn opt -> opt.name end)

    values =
      data.options
      |> Stream.map(fn opt -> opt.value end)
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
end
