defmodule NostrPublisher.Post do
  @moduledoc """
  A struct representing a Nostr NIP-23 long-form content post.
  
  Fields map directly to Nostr event structure:
    - `id` - The `d` tag (unique identifier for replaceable events)
    - `title` - The `title` tag
    - `author` - The event's `pubkey`
    - `body` - HTML content (converted from markdown by NimblePublisher)
    - `description` - The `summary` tag
    - `tags` - List of `t` tags (topic tags)
    - `date` - Date from `published_at` tag
    - `image` - The `image` tag (optional)
    - `created_at` - Unix timestamp from event (optional)
  """

  @enforce_keys [:id, :author, :title, :body, :date]
  defstruct [:id, :author, :title, :body, :description, :tags, :date, :image, :created_at]

  @doc """
  Builds a Post from parsed Nostr event attributes.
  
  Unlike traditional NimblePublisher posts, the filename is ignored - all
  metadata comes from the Nostr event's tags and fields.
  """
  def build(_filename, attrs, body) do
    struct!(
      __MODULE__,
      Map.put(attrs, :body, body)
      |> Map.put_new(:tags, [])
      |> Map.put_new(:description, nil)
      |> Map.put_new(:image, nil)
      |> Map.put_new(:created_at, nil)
    )
  end
end

