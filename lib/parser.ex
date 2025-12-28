defmodule NostrPublisher.Parser do
  @moduledoc """
  Parser for Nostr NIP-23 (kind 30023) long-form content events.
  
  Parses JSON files containing Nostr events and extracts metadata from tags
  and content from the event's content field.
  """

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
    case Jason.decode(contents) do
      {:ok, event} ->
        attrs = extract_attrs(event)
        body = Map.get(event, "content", "")
        {attrs, body}
      
      {:error, reason} ->
        raise "Failed to parse Nostr event JSON: #{inspect(reason)}"
    end
  end

  defp extract_attrs(event) do
    tags = Map.get(event, "tags", [])
    
    %{
      id: get_tag_value(tags, "d"),
      title: get_tag_value(tags, "title"),
      description: get_tag_value(tags, "summary"),
      author: Map.get(event, "pubkey"),
      created_at: Map.get(event, "created_at"),
      date: parse_date(tags),
      tags: get_all_tag_values(tags, "t"),
      image: get_tag_value(tags, "image")
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp get_tag_value(tags, tag_name) do
    case Enum.find(tags, fn [name | _] -> name == tag_name end) do
      [_name, value | _] -> value
      _ -> nil
    end
  end

  defp get_all_tag_values(tags, tag_name) do
    tags
    |> Enum.filter(fn [name | _] -> name == tag_name end)
    |> Enum.map(fn [_name, value | _] -> value end)
    |> case do
      [] -> nil
      values -> values
    end
  end

  defp parse_date(tags) do
    case get_tag_value(tags, "published_at") do
      nil -> nil
      timestamp_string ->
        case Integer.parse(timestamp_string) do
          {timestamp, _} -> 
            timestamp
            |> DateTime.from_unix!()
            |> DateTime.to_date()
          
          :error -> nil
        end
    end
  end
end

