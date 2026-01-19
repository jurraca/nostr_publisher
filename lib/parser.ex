defmodule NostrPublisher.Parser do
  @moduledoc """
  Parser for Nostr NIP-23 (kind 30023) long-form content events.

  Parses JSON files containing Nostr events and extracts metadata from tags
  and content from the event's content field.
  """

  alias Nostr.Tag

  @doc """
  Parses a Nostr event JSON file.

  ## Parameters

    - `path` - The file path (used for error messages)
    - `contents` - The JSON string containing the Nostr event

  ## Returns

  Returns `{attrs, body}` where:
    - `attrs` is a map with atom keys containing metadata extracted from tags
    - `body` is the markdown content from the event's content field

  ## Tag Mapping

  Nostr tags are mapped to attributes as follows:
    - `d` tag → `:id` (unique identifier for the article)
    - `title` tag → `:title`
    - `published_at` tag → `:date` (converted to Date struct)
    - `summary` tag → `:description`
    - `t` tags (can be multiple) → `:tags` (list of topic tags)
    - Event's `pubkey` → `:author`
    - Event's `created_at` → `:created_at` (Unix timestamp)
  """
  def parse(_path, contents) do
    case JSON.decode(contents) do
      {:ok, event} ->
        attrs = extract_attrs(event)
        body = Map.get(event, "content", "")
        {attrs, body}

      {:error, reason} ->
        raise "Failed to parse Nostr event JSON: #{inspect(reason)}"
    end
  end

  defp extract_attrs(event) do
    tags =
      Map.get(event, "tags", [])
      |> get_all_tags()

    %{
      id: Map.get(tags, "d") || Map.get(event, "id"),
      event_id: Map.get(event, "id"),
      author: Map.get(event, "pubkey"),
      title: Map.get(tags, "title"),
      summary: Map.get(tags, "summary"),
      published_at: parse_date(tags),
      image: Map.get(tags, "image"),
      created_at: Map.get(event, "created_at")
    }
  end

  defp get_tag_value(tags, tag_name) do
    Enum.find_value(tags, fn
      %Tag{type: ^tag_name} = tag -> Map.get(tag, :data)
      _ -> nil
    end)
  end

  defp get_all_tags(tags) do
    tags
    |> Enum.filter(fn tag -> Map.get(tag, :type) != nil end)
    |> Enum.reduce(%{}, fn tag, acc ->
      {k, v} = parse_tag(tag)
      Map.put(acc, k, v)
    end)
  end

  defp parse_tag(%Tag{type: type, data: data, info: []}), do: {type, data}
  defp parse_tag(%Tag{type: type, data: data, info: info}), do: {type, {data, info}}

  defp get_all_tag_values(tags, tag_name) do
    tags
    |> Enum.filter(fn tag -> Map.get(tag, :type) == tag_name end)
    |> Enum.map(fn
      %Tag{data: data} -> data
      _ -> nil
    end)
  end

  defp parse_date(tags) do
    case get_tag_value(tags, "published_at") do
      nil ->
        nil

      timestamp_string ->
        case Integer.parse(timestamp_string) do
          {timestamp, _} ->
            timestamp
            |> DateTime.from_unix!()
            |> DateTime.to_date()

          :error ->
            nil
        end
    end
  end
end
