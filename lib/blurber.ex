defmodule Blurber do
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
end
