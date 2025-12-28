# NostrPublisher

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `nostr_publisher` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:nostr_publisher, "~> 0.1.0"}
  ]
end
```

## Usage

`NostrPublisher` is essentially a plugin for `NimblePublisher`, with a Nostr client.
In our own blog application, we want to pass `NostrPublisher` modules into `NimblePublisher`'s `use` config as below.

Example of a module in your `MyBlog` application: 

```
defmodule MyBlog.Blog do
  @moduledoc """
  Example blog module using NimblePublisher with Nostr events.
  """

  alias NostrPublisher.Post

  use NimblePublisher,
    build: Post,
    from: Application.app_dir(:nimble_publisher, "priv/posts/**/*.json"),
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

You should set `relays` and `filters` to specify the author(s) to fetch and where to fetch them from.
You should also set a `frequency` to run the check schedule on.

```
# config/config.exs
config :nimble_publisher, NimblePublisher.NostrScheduler,
  frequency: :timer.hours(8),
  relays: ["wss://relay.damus.io", "wss://nos.lol"],
  filters: [authors: ["pubkey"], kinds: [30023]],
  output_dir: "priv/posts",
  reload_module: "lib/my_app/blog.ex"
```

