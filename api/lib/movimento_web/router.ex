defmodule MovimentoWeb.Router do
  use MovimentoWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api/json" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4

    forward "/", MovimentoWeb.AshJsonApiRouter
  end

  scope "/api", MovimentoWeb do
    pipe_through :api
  end
end
