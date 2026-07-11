defmodule MovimentoApiWeb.Router do
  use MovimentoApiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api/json" do
    pipe_through [:api]

    forward "/swaggerui", OpenApiSpex.Plug.SwaggerUI,
      path: "/api/json/open_api",
      default_model_expand_depth: 4

    forward "/", MovimentoApiWeb.AshJsonApiRouter
  end

  scope "/api", MovimentoApiWeb do
    pipe_through :api
  end
end
