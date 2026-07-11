defmodule ApiWeb.Router do
  use ApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api/json" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4

    forward "/", ApiWeb.AshJsonApiRouter
  end

  scope "/api", ApiWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end
end
