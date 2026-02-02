defmodule NostrPublisher.Fetcher do
  @moduledoc """
  Fetches Nostr long-form content events (kind 30023) from relays and saves them
  as JSON files on disk.

  This module handles subscribing to Nostr relays, receiving events, and writing
  them to the filesystem. Events are saved using their `d` tag as the filename,
  so updates to the same article (same `d` tag) will replace the previous version.
  """

  use GenServer
  require Logger

  @doc """
  Starts the fetcher process.

  ## Options

    - `:relays` - List of relay URLs to connect to
    - `:filters` - Map of filter criteria (authors, kinds, since, etc.)
    - `:output_dir` - Directory where JSON files will be saved
    - `:schedule_minutes` - How often to poll for events
    - `:reload_module` - Path to blog module file to reload after fetching (optional)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    relays = Keyword.fetch!(opts, :relays)
    filters = Keyword.fetch!(opts, :filters)
    output_dir = Keyword.fetch!(opts, :output_dir)
    schedule_minutes = Keyword.get(opts, :schedule_minutes, 60)
    reload_module = Keyword.get(opts, :reload_module)

    File.mkdir_p!(output_dir)

    state = %{
      relays: relays,
      output_dir: output_dir,
      schedule_minutes: schedule_minutes,
      reload_module: reload_module,
      events: []
    }

    case NostrEx.create_sub(filters) do
      {:ok, sub} ->
        state = Map.put(state, :subscription, sub)
        send(self(), :connect_and_subscribe)
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_info(:connect_and_subscribe, %{subscription: sub} = state) do
    connected_relays = NostrEx.list_relays()

    if connected_relays == [] do
      Enum.each(state.relays, fn relay_url -> NostrEx.connect(relay_url) end)
    end

    NostrEx.listen(sub.id)

    case NostrEx.send_sub(sub) do
      {:ok, sub_id} ->
        Logger.info("Subscribed with ID: #{sub_id}")
        {:noreply, state}

      {:error, _reason} ->
        cleanup_relays()
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:event, _sub_id, event}, state) do
    d_tag = get_d_tag(event)
    if d_tag in state.events do
      {:noreply, state}
    else
      case process_event(event, state.output_dir) do
        :ok ->
          new_state = %{state | events: [d_tag | state.events]}
          {:noreply, new_state}
  
        {:error, reason} ->
          Logger.warning("Failed to process event: #{inspect(reason)}")
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({:eose, _sub_id, relay_host}, state) do
    Logger.info("EOSE received from #{relay_host}, disconnecting.")
    NostrEx.disconnect(relay_host)

    # If no more connected relays,
    # hot-reload blog module if configured and we received events
    # schedule another fetch according to schedule
    if NostrEx.list_relays() == [] do
      if Map.get(state, :reload_module) do
        reload_module(state.reload_module)
      end
      Process.send_after(self(), :connect_and_subscribe, state.schedule_minutes * 60_000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:stop, state) do
    cleanup_relays()
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    cleanup_relays()
    :ok
  end

  defp reload_module(module_path) do
    try do
      Code.compile_file(module_path)
    rescue
      error ->
        Logger.error("Failed to reload module: #{inspect(error)}")
    end
  end

  defp cleanup_relays() do
    NostrEx.list_relays()
    |> Enum.each(fn relay_name ->
      case NostrEx.disconnect(relay_name) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error("Error disconnecting from #{relay_name}: #{inspect(reason)}")
      end
    end)
  end

  # Write the event to the local file system, if it does not exist yet.
  # events are indexed by their d_tag.
  # without d_tag, we use the first 8 chars of the event ID and its created_at timestamp
  # and will get new events written for every revision of the Post
  defp process_event(%{kind: 30023, tags: tags, created_at: created_at} = event, output_dir) do
    ts = DateTime.to_unix(created_at) |> Integer.to_string()

    filename =
      case get_d_tag(tags) do
        %{data: d_tag_data} ->
          sanitize_filename(d_tag_data) <> ".json"

        _ ->
          String.slice(event.id, 0..8) <> "_" <> ts <> ".json"
      end

    filepath = Path.join(output_dir, filename)

    if not File.exists?(filepath) do
      json = JSON.encode!(event)
      File.write(filepath, json)
      :ok
    else
      {:error, :already_written}
    end
  end

  defp process_event(_event, _output_dir), do: {:error, :invalid_kind}

  defp get_d_tag(tags) when is_list(tags) do
    Enum.find_value(tags, fn tag ->
      d = Map.get(tag, :d)
      if(d, do: d)
    end)
  end

  defp get_d_tag(_event), do: nil

  defp sanitize_filename(d_tag) do
    # Replace characters that might be problematic in filenames
    d_tag
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "_")
    # Limit length
    |> String.slice(0, 50)
  end
end
