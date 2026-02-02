defmodule NostrPublisher.Parser do
  @moduledoc """
  Parser for Nostr NIP-23 (kind 30023) long-form content events.

  Parses JSON files containing Nostr events and extracts metadata from tags
  and content from the event's content field.
  """

  alias Nostr.Event

  @doc """
  Parses a Nostr event JSON file.
  Uses `Nostr.Event.Article.parse/1` from `nostr_lib`.

  ## Parameters

    - `path` - The file path (used for error messages)
    - `contents` - The JSON string containing the Nostr event

  ## Returns

  Returns `{attrs, body}` where:
    - `attrs` is a map with atom keys containing metadata extracted from tags
    - `body` is the markdown content from the event's content field

  ## Tag Mapping

  See https://hexdocs.pm/nostr_lib/Nostr.Event.Article.html
  """
  def parse(_path, contents) do
    case JSON.decode(contents) do
      {:ok, decoded} ->
        article = decoded
          |> Event.parse()
          |> Event.Article.parse()
          |> Map.from_struct()

        if Map.get(article, :content) do
          # NimblePublisher expects a tuple {attrs, body}
          {article, article.content}
        else
          {:error, "no content found for event"}
        end

      {:error, reason} ->
        raise "Failed to parse Nostr event JSON: #{inspect(reason)}"
    end
  end
end
