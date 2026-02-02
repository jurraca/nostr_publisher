# NostrPublisher

A [NimblePublisher](https://hexdocs.pm/nimble_publisher/NimblePublisher.html) plugin for Nostr long-form events.

NimblePublisher is "minimal filesystem-based publishing engine with Markdown support and code highlighting".

Nostr has an event kind for blog posts or "long-form" text, which is kind `30023`, defined by NIP [23](https://github.com/nostr-protocol/nips/blob/master/23.md).

This plugin takes configuration in the form of Nostr filters (which authors and event types to fetch, and where to find them),
and saves the events to the local filesystem. The `NostrPublisher.Parser` parses the event data and builds a post.

Publish from anywhere, in markdown, and it will appear on your blog automagically.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `nostr_publisher` to your list of dependencies in `mix.exs`:

You will also need `NimblePublisher`.
```elixir
def deps do
  [
    {:nimble_publisher, "~> 1.1.1"},
    {:nostr_publisher, "~> 0.1.0"}
  ]
end
```

## Usage

`NostrPublisher` is essentially a plugin for `NimblePublisher`, with a Nostr client.
In our own blog application, we want to pass `NostrPublisher` modules into `NimblePublisher`'s `use` config as below.

Example of a module in your `MyBlog` application: 

```elixir
defmodule MyBlog.Blog do
  @moduledoc """
  Example blog module using NimblePublisher with Nostr events.
  """

  use NimblePublisher,
    build: MyBlog.Post,
    from: Application.app_dir(:myblog, "priv/posts/**/*.json"),
    as: :posts,
    parser: NostrPublisher.Parser,
    highlighters: []

  @posts Enum.sort_by(@posts, & &1.date, {:desc, Date})

  @tags @posts |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

  def all_posts, do: @posts
  def all_tags, do: @tags

  def get_post_by_id(id) do
    Enum.find(@posts, &(&1.id == id))
  end

  def get_posts_by_tag(tag) do
    Enum.filter(@posts, &(tag in &1.tags))
  end

  @doc """
  Reloads this module to pick up new Nostr events.
  
  Call this after NostrPublisher.Fetcher saves new events to disk.
  """
  def reload! do
    Code.compile_file(__ENV__.file)
    :ok
  end
end
```

## Configuration

In your web application (here called `myblog`), configure `NostrPublisher`.
You should set `relays` and `filters` to specify the author(s) to fetch and where to fetch them from.

```elixir
# config/runtime.exs
config :myblog, NostrPublisher,
  relays: ["wss://relay.damus.io", "wss://nos.lol"],
  filters: [authors: ["mylongpubkey"], kinds: [30023]],
  output_dir: "priv/posts",
  reload_module: "lib/my_app/blog.ex"
```

However, it is simpler to override the config defaults in `runtime.exs` by setting `AUTHORS` and `RELAYS` environment variables of comma separated values, which get picked up at runtime.
