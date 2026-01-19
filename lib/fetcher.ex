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
      events: %{},
      sub_id: nil
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
  def handle_info(:connect_and_subscribe, state) do
    Logger.info("Connecting to Nostr relays: #{inspect(state.relays)}")
    Enum.each(state.relays, fn relay_url -> NostrEx.connect(relay_url) end)

    connected_relays = NostrEx.list_relays()

    if connected_relays == [] do
      Logger.error("Failed to connect to any relays")
      {:stop, :normal, state}
    else
      sub = state.subscription
      NostrEx.listen(sub.id)

      case NostrEx.send_sub(sub, send_via: connected_relays) do
        {:ok, sub_id} ->
          Logger.info("Subscribed with ID: #{sub_id}")
          {:noreply, %{state | sub_id: sub_id}}

        {:error, reason} ->
          Logger.error("Failed to subscribe: #{inspect(reason)}")
          cleanup_relays()
          {:noreply, state}
      end
    end
  end

  @impl true
  def handle_info({:event, _sub_id, event}, state) do
    case process_event(event, state.output_dir) do
      :ok ->
        d_tag = get_d_tag(event)
        new_state = %{state | events: Map.put(state.events, d_tag, event)}
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("Failed to process event: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:eose, _sub_id, relay_host}, state) do
    Logger.debug("EOSE received from #{relay_host}")
    NostrEx.disconnect(relay_host)

    # Hot-reload blog module if configured and we received events
    if Map.get(state, :reload_module) && map_size(state.events) > 0 do
      reload_module(state.reload_module)
    end

    # If no more connected relays,
    # schedule another fetch according to schedule
    if NostrEx.list_relays() == [] do
      Process.send_after(self(), :connect_and_subscribe, state.schedule_minutes * 3600)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:stop, state) do
    Logger.info("Fetching complete. Received #{map_size(state.events)} events.")
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
    Logger.info("Reloading module: #{module_path}")

    try do
      Code.compile_file(module_path)
      Logger.info("Module reloaded successfully")
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
          Logger.debug("Error disconnecting from #{relay_name}: #{inspect(reason)}")
      end
    end)
  end

  defp process_event(%{kind: 30023, tags: tags, created_at: created_at} = event, output_dir) do
    ts = DateTime.to_unix(created_at) |> Integer.to_string()

    filename =
      case get_d_tag(tags) do
        %{data: d_tag_data} ->
          sanitize_filename(d_tag_data) <> "_" <> ts <> ".json"

        _ ->
          String.slice(event.id, 0..8) <> "_" <> ts <> ".json"
      end

    filepath = Path.join(output_dir, filename)

    if not File.exists?(filepath) do
      json =
        event
        |> Map.from_struct()
        |> Map.update!(:tags, fn tags ->
          Enum.map(tags, &Map.from_struct/1)
        end)
        |> JSON.encode!()

      File.write(filepath, json)
      :ok
    else
      {:error, :already_written}
    end
  end

  defp process_event(_event, _output_dir), do: {:error, :invalid_kind}

  defp get_d_tag(tags) when is_list(tags) do
    Enum.find_value(tags, fn %{type: :d} = tag -> tag end)
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
