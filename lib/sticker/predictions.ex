defmodule Sticker.Predictions do
  @moduledoc """
  The Predictions context.
  """

  import Ecto.Query, warn: false
  alias Sticker.Repo

  alias Sticker.Predictions.Prediction

  @doc """
  Moderates a prediction.
  The logic in replicate_webhook_controller.ex handles
  the webhook. Once the moderation is complete, the webhook controller automatically
  called gen_image.
  """
  def moderate(prompt, user_id, prediction_id) do
    "fofr/prompt-classifier"
    |> Replicate.Models.get!()
    |> Replicate.Models.get_latest_version!()
    |> Replicate.Predictions.create(
      %{
        prompt: "[PROMPT] #{prompt} [/PROMPT] [SAFETY_RANKING]",
        max_new_tokens: 128,
        temperature: 0.2,
        top_p: 0.9,
        top_k: 50,
        stop_sequences: "[/SAFETY_RANKING]"
      },
      "#{Sticker.Utils.get_host()}/webhooks/replicate?user_id=#{user_id}&prediction_id=#{prediction_id}"
    )
  end

  def gen_image(prompt, user_id, prediction_id) do
    "fofr/sticker-maker"
    |> Replicate.Models.get!()
    |> Replicate.Models.get_latest_version!()
    |> Replicate.Predictions.create(
      %{
        prompt: prompt,
        width: 512,
        height: 512,
        num_inference_steps: 20,
        negative_prompt: "racist, xenophobic, antisemitic, islamophobic, bigoted",
        upscale: false
      },
      "#{Sticker.Utils.get_host()}/webhooks/replicate?user_id=#{user_id}&prediction_id=#{prediction_id}"
    )
  end

  def list_loading_predictions(nil), do: []

  def list_loading_predictions(user_id) do
    from(p in Prediction,
      where:
        p.local_user_id == ^user_id and
          (p.status != :succeeded and
             (p.moderation_score < 9 and p.status == :moderation_succeeded)),
      order_by: [desc: p.inserted_at]
    )
    |> Repo.all()
  end

  def get_predictions(ids) do
    from(p in Prediction, where: p.id in ^ids and not is_nil(p.sticker_output)) |> Repo.all()
  end

  def count_predictions_with_text_embeddings() do
    Repo.aggregate(
      from(p in Prediction, where: not p.embedding |> is_nil()),
      :count
    )
  end

  def count_predictions_with_image_embeddings() do
    Repo.aggregate(
      from(p in Prediction, where: not p.image_embedding |> is_nil()),
      :count
    )
  end

  def get_random_prediction_without_text_embeddings() do
    from(p in Prediction,
      where: is_nil(p.embedding) and not is_nil(p.sticker_output) and p.score != 10,
      order_by: fragment("RANDOM()"),
      limit: 1
    )
    |> Repo.one()
  end

  def get_random_prediction_without_image_embeddings() do
    from(p in Prediction,
      where: is_nil(p.image_embedding) and not is_nil(p.sticker_output) and p.score != 10,
      order_by: fragment("RANDOM()"),
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns the list of predictions.

  ## Examples

      iex> list_predictions()
      [%Prediction{}, ...]

  """
  def list_predictions do
    Repo.all(Prediction)
  end

  def list_predictions_with_text_embeddings do
    Repo.all(
      from p in Prediction, where: not is_nil(p.embedding) and not is_nil(p.sticker_output)
    )
  end

  def list_predictions_with_image_embeddings do
    Repo.all(
      from p in Prediction, where: not is_nil(p.image_embedding) and not is_nil(p.sticker_output)
    )
  end

  def paginate(query, page, per_page) do
    offset_by = per_page * page

    query
    |> limit(^per_page)
    |> offset(^offset_by)
  end

  def get_oldest_safe_prediction() do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and p.moderation_score <= 5 and p.is_featured == true,
      order_by: [asc: p.updated_at],
      limit: 1
    )
    |> Repo.one()
  end

  def list_latest_predictions_no_moderation(page, per_page \\ 20) do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and p.moderation_score <= 5 and is_nil(p.is_featured),
      order_by: [desc: p.inserted_at]
    )
    |> paginate(page, per_page)
    |> Repo.all()
  end

  def list_latest_predictions(page, per_page \\ 20) do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and p.moderation_score <= 5,
      order_by: [desc: p.inserted_at]
    )
    |> paginate(page, per_page)
    |> Repo.all()
  end

  def list_latest_safe_predictions(page, per_page \\ 20) do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and p.moderation_score <= 5 and p.is_featured == true,
      order_by: [desc: p.updated_at]
    )
    |> paginate(page, per_page)
    |> Repo.all()
  end

  def number_predictions() do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and p.moderation_score <= 5,
      order_by: [desc: p.inserted_at]
    )
    |> Repo.aggregate(:count)
  end

  def number_safe_predictions() do
    from(p in Prediction,
      where: not is_nil(p.sticker_output) and p.moderation_score <= 5 and p.is_featured == true,
      order_by: [desc: p.inserted_at]
    )
    |> Repo.aggregate(:count)
  end

  def list_user_predictions(user_id) do
    Repo.all(
      from p in Prediction,
        where: p.local_user_id == ^user_id,
        order_by: [desc: p.inserted_at],
        where: not is_nil(p.sticker_output)
    )
  end

  def list_finished_predictions() do
    Repo.all(
      from p in Prediction,
        where: not is_nil(p.no_bg_output) and p.score > 3 and p.count_votes > 5,
        order_by: fragment("RANDOM()"),
        limit: 16
    )
  end

  def list_featured_predictions() do
    Repo.all(
      from p in Prediction,
        where:
          p.is_featured == true or
            (not is_nil(p.no_bg_output) and p.score > 3 and p.count_votes > 5),
        order_by: fragment("RANDOM()"),
        limit: 16
    )
  end

  @doc """
  Gets a single prediction.

  Raises `Ecto.NoResultsError` if the Prediction does not exist.

  ## Examples

      iex> get_prediction!(123)
      %Prediction{}

      iex> get_prediction!(456)
      ** (Ecto.NoResultsError)

  """
  def get_prediction!(id), do: Repo.get!(Prediction, id)

  @doc """
  Creates a prediction.

  ## Examples

      iex> create_prediction(%{field: value})
      {:ok, %Prediction{}}

      iex> create_prediction(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_prediction(attrs \\ %{}) do
    %Prediction{}
    |> Prediction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a prediction.

  ## Examples

      iex> update_prediction(prediction, %{field: new_value})
      {:ok, %Prediction{}}

      iex> update_prediction(prediction, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_prediction(%Prediction{} = prediction, attrs) do
    prediction
    |> Prediction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a prediction.

  ## Examples

      iex> delete_prediction(prediction)
      {:ok, %Prediction{}}

      iex> delete_prediction(prediction)
      {:error, %Ecto.Changeset{}}

  """
  def delete_prediction(%Prediction{} = prediction) do
    Repo.delete(prediction)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking prediction changes.

  ## Examples

      iex> change_prediction(prediction)
      %Ecto.Changeset{data: %Prediction{}}

  """
  def change_prediction(%Prediction{} = prediction, attrs \\ %{}) do
    Prediction.changeset(prediction, attrs)
  end
end
