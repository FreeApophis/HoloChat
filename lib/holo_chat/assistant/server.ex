defmodule HoloChat.Assistant.Server do
  @moduledoc """
  Runs the assistant personas in their rooms.

  It listens to every room that has a persona and, while the assistant is
  enabled, queues each message that mentions a persona there as `@Name`.
  All personas share one queue and answer one at a time, because a local
  model server generates one reply at a time anyway. Generation runs in a
  task so the server stays responsive.

  Status changes are broadcast per room and persona as
  `{:assistant_status, %{room:, name:, persona_id:, avatar_id:, online:, typing:}}`
  on the assistant topic (see `HoloChat.Assistant.subscribe/0`). Sending
  `:assistant_status_request` on that topic makes the server re-announce.
  """

  use GenServer

  require Logger

  alias HoloChat.{Assistant, Chat}
  alias HoloChat.Assistant.LLM

  @max_queue 10
  @apology "Sorry, I can't answer right now. Please try again later."

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    Assistant.subscribe()

    state = %{
      settings: Assistant.get_settings(),
      personas: [],
      rooms: MapSet.new(),
      announced: MapSet.new(),
      queue: :queue.new(),
      task: nil,
      task_supervisor: Keyword.get(opts, :task_supervisor, HoloChat.Assistant.TaskSupervisor)
    }

    {:ok, state |> load_personas() |> announce()}
  end

  @impl true
  def handle_info({:new_message, message}, state) do
    {:noreply, state |> enqueue_mentions(message) |> maybe_start_next()}
  end

  def handle_info({:assistant_settings_changed, settings}, state) do
    {:noreply, announce(%{state | settings: settings})}
  end

  def handle_info({:assistant_personas_changed}, state) do
    {:noreply, state |> load_personas() |> announce()}
  end

  def handle_info(:assistant_status_request, state) do
    {:noreply, announce(%{state | announced: MapSet.new()})}
  end

  def handle_info({:assistant_status, _status}, state), do: {:noreply, state}

  def handle_info({ref, result}, %{task: {ref, persona, message}} = state) do
    Process.demonitor(ref, [:flush])
    post_reply(result, persona, message)
    {:noreply, %{state | task: nil} |> announce() |> maybe_start_next()}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: {ref, persona, message}} = state) do
    post_reply({:error, {:crashed, reason}}, persona, message)
    {:noreply, %{state | task: nil} |> announce() |> maybe_start_next()}
  end

  # Listens to exactly the rooms that have personas.
  defp load_personas(state) do
    personas = Assistant.list_personas()
    rooms = personas |> Enum.flat_map(& &1.rooms) |> MapSet.new()

    Enum.each(MapSet.difference(state.rooms, rooms), &Chat.unsubscribe/1)
    Enum.each(MapSet.difference(rooms, state.rooms), &Chat.subscribe/1)

    %{state | personas: personas, rooms: rooms}
  end

  defp enqueue_mentions(%{settings: %{enabled: false}} = state, _message), do: state
  defp enqueue_mentions(state, %{from_assistant: true}), do: state

  defp enqueue_mentions(state, message) do
    state.personas
    |> Enum.filter(&(message.room in &1.rooms and Assistant.mentioned?(&1.name, message.body)))
    |> Enum.reduce(state, fn persona, state ->
      if :queue.len(state.queue) < @max_queue,
        do: %{state | queue: :queue.in({persona, message}, state.queue)},
        else: state
    end)
  end

  defp maybe_start_next(%{task: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, {persona, message}}, queue} ->
        endpoint_url = state.settings.endpoint_url

        task =
          Task.Supervisor.async_nolink(state.task_supervisor, fn ->
            generate(endpoint_url, persona, message)
          end)

        announce(%{state | queue: queue, task: {task.ref, persona, message}})

      {:empty, _queue} ->
        state
    end
  end

  defp maybe_start_next(state), do: state

  # Context: the messages before the mention, plus the mention itself.
  defp generate(endpoint_url, persona, message) do
    {history, _more?} =
      Chat.list_messages_page(message.room, message, persona.context_messages - 1)

    prompt = Assistant.build_prompt(persona, history ++ [message])

    with {:ok, text} <-
           LLM.impl().chat(endpoint_url, prompt,
             max_tokens: persona.max_tokens,
             temperature: persona.temperature
           ) do
      case Assistant.clean_reply(persona.name, text) do
        nil -> {:error, :empty_reply}
        reply -> {:ok, reply}
      end
    end
  end

  defp post_reply({:ok, reply}, persona, message) do
    Chat.create_assistant_message(message.room, persona.name, reply, persona_id: persona.id)
  end

  defp post_reply({:error, reason}, persona, message) do
    Logger.warning("Assistant #{persona.name} could not answer: #{inspect(reason)}")
    Chat.create_assistant_message(message.room, persona.name, @apology, persona_id: persona.id)
  end

  # Announces every room/persona pair that is online, and takes pairs
  # that were online before but no longer are (persona removed, renamed,
  # moved or assistant disabled) offline.
  defp announce(state) do
    # {room, name} => persona, for every pair that should be online.
    online =
      if state.settings.enabled,
        do: Map.new(for(p <- state.personas, room <- p.rooms, do: {{room, p.name}, p})),
        else: %{}

    typing =
      case state.task do
        {_ref, persona, message} -> {message.room, persona.name}
        nil -> nil
      end

    for {{room, _name} = pair, persona} <- online do
      broadcast_status(room, persona, %{online: true, typing: pair == typing})
    end

    for {room, name} <- MapSet.difference(state.announced, MapSet.new(Map.keys(online))) do
      broadcast_status(room, %{id: nil, name: name, avatar_id: nil}, %{
        online: false,
        typing: false
      })
    end

    %{state | announced: MapSet.new(Map.keys(online))}
  end

  defp broadcast_status(room, persona, flags) do
    status = %{
      room: room,
      name: persona.name,
      persona_id: persona.id,
      avatar_id: persona.avatar_id
    }

    Assistant.broadcast({:assistant_status, Map.merge(status, flags)})
  end
end
