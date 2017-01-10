defmodule Sentinel.Controllers.Html.UserController do
  @moduledoc """
  Handles the user create, confirm and invite actions
  """

  use Phoenix.Controller
  alias Sentinel.Changeset.Confirmator
  alias Sentinel.Changeset.PasswordResetter
  alias Sentinel.Config
  alias Sentinel.Util

  @doc """
  Confirm either a new user or an existing user's new email address.
  Parameter "id" should be the user's id.
  Parameter "confirmation" should be the user's confirmation token.
  If the confirmation matches, the user will be confirmed and signed in.
  """
  def confirm(conn, params) do
    case do_confirm(params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Successfully confirmed your account")
        |> redirect(to: "/")
      {:error, changeset} ->
        conn
        |> put_status(422)
        |> put_flash(:error, "Unable to confirm your account")
        |> redirect(to: "/")
    end
  end

  defp do_confirm(params) do
    Config.user_model
    |> Config.repo.get_by(email: params["email"])
    |> Config.user_model.changeset(params)
    |> Confirmator.confirmation_changeset
    |> Config.repo.update
  end

  def invited(conn, params) do
    case do_invited(params) do
      {:ok, user} ->
        conn
        |> Guardian.Plug.sign_in(user)
        |> put_flash(:info, "Signed up")
        |> redirect(to: Config.router_helper.account_path(Config.endpoint, :edit))
      {:error, changeset} ->
        conn
        |> put_status(422)
        |> put_flash(:error, "Failed to create user")
        |> render(Sentinel.SessionView, "new.html", %{conn: conn, changeset: changeset, providers: Config.ueberauth_providers})
    end
  end

  # FIXME move into another module
  defp do_invited(%{"id" => id} = params) do
    user = Config.repo.get(Config.user_model, id)
    auth = Config.repo.get_by(Sentinel.Ueberauth, provider: "identity", user_id: user.id)

    auth_params = Util.params_to_ueberauth_auth_struct(params)
    auth_changeset = PasswordResetter.reset_changeset(auth, auth_params)
    user_changeset =
      user
      |> Config.user_model.changeset(%{confirmation_token: params["confirmation_token"]})
      |> Confirmator.confirmation_changeset

    case {Config.repo.update(auth_changeset), Config.repo.update(user_changeset)} do
      {{:ok, _auth}, {:ok, updated_user}} -> {:ok, updated_user}
      {{:error, _}, _} -> {:error, auth_changeset}
      {_, {:error, _}} -> {:error, user_changeset}
    end
  end
end
