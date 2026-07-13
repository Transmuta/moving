defmodule ApiTest do
  @moduledoc """
  `Api.web_app_url/0` — fonte única da URL do web (auditoria doc 13, causa I): antes estava
  duplicada em três módulos. Reflete o config `:web_app_url`.
  """
  use ExUnit.Case, async: false

  test "web_app_url/0 reflete o config :web_app_url" do
    original = Application.get_env(:api, :web_app_url)
    Application.put_env(:api, :web_app_url, "https://exemplo.test")

    on_exit(fn ->
      if original do
        Application.put_env(:api, :web_app_url, original)
      else
        Application.delete_env(:api, :web_app_url)
      end
    end)

    assert Api.web_app_url() == "https://exemplo.test"
  end
end
