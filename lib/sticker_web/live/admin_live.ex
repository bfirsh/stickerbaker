defmodule StickerWeb.AdminLive do
  use StickerWeb, :live_view
  alias Phoenix.PubSub
  alias Sticker.Predictions

  def mount(_params, session, socket) do
    page = 0
    per_page = 20
    max_pages = Predictions.number_predictions() / per_page
    autoplay = Sticker.Autoplay.get_state()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sticker.PubSub, "prediction-firehose")
    end

    {:ok,
     socket
     |> assign(autoplay: autoplay)
     |> assign(local_user_id: session["local_user_id"])
     |> assign(page: page)
     |> assign(per_page: per_page)
     |> assign(max_pages: max_pages)
     |> assign(number_predictions: Predictions.number_predictions())
     |> stream(:latest_predictions, list_latest_predictions_no_moderation(page, per_page))}
  end

  defp list_latest_predictions_no_moderation(page, per_page) do
    Predictions.list_latest_predictions_no_moderation(page, per_page)
  end

  def handle_event("toggle-autoplay", _params, socket) do
    if socket.assigns.autoplay do
      Sticker.Autoplay.deactivate()
    else
      Sticker.Autoplay.activate()
    end

    # Fetch the new state to ensure consistency
    new_state = Sticker.Autoplay.get_state()

    # Update the socket with the new state and re-render
    {:noreply,
     assign(socket, autoplay: new_state)
     |> put_flash(:info, "Autoplay should be #{new_state}. Check the home page to confirm.")}
  end

  def handle_event("load-more", _, %{assigns: assigns} = socket) do
    next_page = assigns.page + 1

    latest_predictions =
      list_latest_predictions_no_moderation(assigns.page, socket.assigns.per_page)

    {:noreply,
     socket
     |> assign(page: next_page)
     |> stream(:latest_predictions, latest_predictions)}
  end

  def handle_event("allow", %{"id" => id}, socket) do
    prediction = Predictions.get_prediction!(id)

    set_featured_to = if prediction.is_featured == true, do: nil, else: true

    {:ok, prediction} =
      Predictions.update_prediction(prediction, %{"is_featured" => set_featured_to})

    Phoenix.PubSub.broadcast(
      Sticker.PubSub,
      "safe-prediction-firehose",
      {:new_prediction, prediction}
    )

    {:noreply, socket |> stream_insert(:latest_predictions, prediction)}
  end

  def handle_event("unallow", %{"id" => id}, socket) do
    prediction = Predictions.get_prediction!(id)

    set_featured_to = if prediction.is_featured == false, do: nil, else: false

    {:ok, prediction} =
      Predictions.update_prediction(prediction, %{"is_featured" => set_featured_to})

    {:noreply, socket |> stream_insert(:latest_predictions, prediction)}
  end

  def handle_event("validate", %{"prompt" => _prompt}, socket) do
    {:noreply, socket}
  end

  def handle_event("assign-user-id", %{"userId" => user_id}, socket) do
    PubSub.subscribe(Sticker.PubSub, "user:#{user_id}")

    {:noreply, socket |> assign(local_user_id: user_id)}
  end

  def handle_info({:new_prediction, prediction}, socket) do
    {:noreply, socket |> stream_insert(:latest_predictions, prediction, at: 0)}
  end
end
