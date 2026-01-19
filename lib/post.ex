defmodule NostrPublisher.Post do
  @moduledoc """
  A struct representing a Nostr NIP-23 long-form content post.

  Fields map directly to Nostr event structure:
    - `id` - The `d` tag (unique identifier for replaceable events)
    - `event_id` - the event's `id` field
    - `author` - The event's `pubkey`
    - `body` - HTML content (converted from markdown by NimblePublisher)
    - `title` - The `title` optional tag
    - `summary` - The `summary` optional tag
    - `published_at` - the `published_at` optional tag
    - `image` - The `image` optional tag
    - `created_at` - Unix timestamp from event `created_at` field
  """

  @enforce_keys [:id, :author, :body, :created_at]
  defstruct [:id, :event_id, :author, :body, :title, :summary, :published_at, :image, :created_at]

  @doc """
  Builds a Post from parsed Nostr event attributes.

  Unlike traditional NimblePublisher posts, the filename is ignored - all
  metadata comes from the Nostr event's tags and fields.
  """
  def build(_filename, attrs, body) do
    struct!(
      __MODULE__,
      Map.put(attrs, :body, body)
    )
  end
end
