defmodule HoloChat.Assistant.Server do
  @moduledoc """
  Runs the assistant personas in their rooms and plays the cast characters
  in role-play scenes.

  It listens to every room that has a persona or a cast. While the
  assistant is enabled, it queues

    * each message that mentions a persona there as `@Name`, and
    * the turns of cast characters, as decided by
      `HoloChat.Assistant.Director`: once players have been quiet for the
      scene's reply delay, the characters they named (or, with natural
      turns, one at random) answer; a character naming another lets that
      one answer next, up to the scene's limit of AI turns in a row, and
    * requests to write a room's latest reply again
      (`HoloChat.Assistant.regenerate_reply/2`): the new text replaces the
      old one in place and is no new turn.

  Personas and characters share one queue. Up to the settings'
  `parallel_replies` generate at once (as many as the model server runs in
  parallel), but only one per room: a reply must see the replies before it.
  Generation runs in tasks so the server stays responsive.

  Status changes are broadcast per room and speaker as
  `{:assistant_status, %{room:, name:, persona_id:, character_id:, avatar_id:, online:, typing:}}`
  on the assistant topic (see `HoloChat.Assistant.subscribe/0`). Sending
  `:assistant_status_request` on that topic makes the server re-announce.
  """

  use GenServer

  require Logger

  alias HoloChat.{Assistant, Characters, Chat, Rooms}
  alias HoloChat.Assistant.{Director, LLM, ScenePrompt}

  @max_queue 10
  @apology "Sorry, I can't answer right now. Please try again later."

  # Generation settings for cast characters.
  @scene_history 30
  @scene_max_tokens 400
  @scene_temperature 0.8

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    Assistant.subscribe()
    Rooms.subscribe_scenes()

    state = %{
      settings: Assistant.get_settings(),
      personas: [],
      # Room name => %{room:, cast:, timer:, pending:, streak:, last_speaker_id:}
      scenes: %{},
      rooms: MapSet.new(),
      announced: MapSet.new(),
      queue: :queue.new(),
      # Task ref => job, for the replies being generated.
      tasks: %{},
      task_supervisor: Keyword.get(opts, :task_supervisor, HoloChat.Assistant.TaskSupervisor)
    }

    {:ok, state |> load_personas() |> load_scenes() |> subscribe_rooms() |> announce()}
  end

  @impl true
  def handle_info({:new_message, message}, state) do
    {:noreply,
     state
     |> enqueue_mentions(message)
     |> direct_scene(message)
     |> maybe_start_next()}
  end

  def handle_info({:scene_turn, name, message_id}, state) do
    {:noreply, state |> scene_turn(name, message_id) |> maybe_start_next()}
  end

  def handle_info({:scene_changed, _name}, state) do
    {:noreply, state |> load_scenes() |> subscribe_rooms() |> announce()}
  end

  def handle_info({:assistant_settings_changed, settings}, state) do
    {:noreply, %{state | settings: settings} |> announce() |> maybe_start_next()}
  end

  def handle_info({:assistant_personas_changed}, state) do
    {:noreply, state |> load_personas() |> subscribe_rooms() |> announce()}
  end

  # Deleted and rewritten messages take no turn.
  def handle_info({event, _message}, state)
      when event in [:message_deleted, :message_regenerating, :message_updated],
      do: {:noreply, state}

  def handle_info({:regenerate_reply, reply}, state) do
    {:noreply, state |> enqueue_regeneration(reply) |> maybe_start_next()}
  end

  def handle_info(:assistant_status_request, state) do
    {:noreply, announce(%{state | announced: MapSet.new()})}
  end

  def handle_info({:assistant_status, _status}, state), do: {:noreply, state}

  def handle_info({ref, result}, state) when is_map_key(state.tasks, ref) do
    Process.demonitor(ref, [:flush])
    {job, tasks} = Map.pop!(state.tasks, ref)
    post_reply(result, job)
    {:noreply, %{state | tasks: tasks} |> announce() |> maybe_start_next()}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.tasks, ref) do
    {job, tasks} = Map.pop!(state.tasks, ref)
    post_reply({:error, {:crashed, reason}}, job)
    {:noreply, %{state | tasks: tasks} |> announce() |> maybe_start_next()}
  end

  ## Loading personas and scenes

  defp load_personas(state), do: %{state | personas: Assistant.list_personas()}

  # Keeps each scene's turn state across reloads of its settings and cast.
  defp load_scenes(state) do
    scenes =
      Map.new(Rooms.list_staged_scenes(), fn {room, cast} ->
        turns =
          Map.get(state.scenes, room.name, %{
            timer: nil,
            pending: nil,
            streak: 0,
            last_speaker_id: nil
          })

        {room.name, Map.merge(turns, %{room: room, cast: cast})}
      end)

    for {name, %{timer: timer}} <- state.scenes, timer, not Map.has_key?(scenes, name) do
      Process.cancel_timer(timer)
    end

    %{state | scenes: scenes}
  end

  # Listens to exactly the rooms that have personas or a cast.
  defp subscribe_rooms(state) do
    rooms =
      state.personas
      |> Enum.flat_map(& &1.rooms)
      |> MapSet.new()
      |> MapSet.union(MapSet.new(Map.keys(state.scenes)))

    Enum.each(MapSet.difference(state.rooms, rooms), &Chat.unsubscribe/1)
    Enum.each(MapSet.difference(rooms, state.rooms), &Chat.subscribe/1)

    %{state | rooms: rooms}
  end

  ## Personas

  defp enqueue_mentions(%{settings: %{enabled: false}} = state, _message), do: state
  defp enqueue_mentions(state, %{from_assistant: true}), do: state
  defp enqueue_mentions(state, %{kind: "scenario"}), do: state

  defp enqueue_mentions(state, message) do
    state.personas
    |> Enum.filter(&(message.room in &1.rooms and Assistant.mentioned?(&1.name, message.body)))
    |> Enum.reduce(state, &enqueue(&2, {:persona, &1, message}))
  end

  ## Scenes

  defp direct_scene(%{settings: %{enabled: false}} = state, _message), do: state

  defp direct_scene(state, message) do
    case state.scenes[message.room] do
      nil -> state
      scene -> scene_message(state, scene, message)
    end
  end

  # A character spoke: count the turn and let a character it named answer.
  defp scene_message(state, scene, %{from_assistant: true, character_id: id} = message)
       when is_integer(id) do
    scene = %{scene | streak: scene.streak + 1, last_speaker_id: id}
    state = put_scene(state, scene)

    with true <- scene.streak < scene.room.max_ai_turns,
         %{} = speaker <- Enum.find(scene.cast, &(&1.id == id)),
         %{} = next <- Director.next_in_chain(scene.cast, speaker, message.body) do
      enqueue(state, {:character, scene.room.name, next})
    else
      _no_one -> state
    end
  end

  # A new scenario starts: turns owed to the old one are dropped.
  defp scene_message(state, scene, %{kind: "scenario"}) do
    if scene.timer, do: Process.cancel_timer(scene.timer)
    put_scene(state, %{scene | timer: nil, pending: nil, streak: 0, last_speaker_id: nil})
  end

  # A player spoke: wait until the players have been quiet for the delay.
  defp scene_message(state, scene, %{user_id: user_id} = message) when is_integer(user_id) do
    if scene.timer, do: Process.cancel_timer(scene.timer)
    name = scene.room.name
    pending = {message.id, message.body}

    scene = %{
      scene
      | streak: 0,
        pending: pending,
        timer: Process.send_after(self(), {:scene_turn, name, message.id}, scene_delay(scene))
    }

    put_scene(state, scene)
  end

  # Persona replies and other messages don't take part in the scene.
  defp scene_message(state, _scene, _message), do: state

  defp scene_delay(scene), do: :timer.seconds(scene.room.reply_delay)

  defp scene_turn(state, name, message_id) do
    case state.scenes[name] do
      %{pending: {^message_id, text}} = scene ->
        responders =
          Director.responders(scene.cast, text,
            policy: scene.room.reply_policy,
            limit: scene.room.max_ai_turns,
            last_speaker_id: scene.last_speaker_id
          )

        state = put_scene(state, %{scene | pending: nil, timer: nil})
        Enum.reduce(responders, state, &enqueue(&2, {:character, name, &1}))

      _outdated ->
        state
    end
  end

  defp put_scene(state, scene), do: put_in(state.scenes[scene.room.name], scene)

  ## Regeneration

  defp enqueue_regeneration(%{settings: %{enabled: false}} = state, _reply), do: state

  defp enqueue_regeneration(state, reply) do
    job = {:regenerate, reply}
    regenerating? = job in Map.values(state.tasks)
    queued = enqueue(state, job)

    if regenerating? or queued == state do
      state
    else
      Chat.announce_regenerating(reply)
      queued
    end
  end

  ## The shared queue

  defp enqueue(state, job) do
    queued? = job in :queue.to_list(state.queue)

    if queued? or :queue.len(state.queue) >= @max_queue,
      do: state,
      else: %{state | queue: :queue.in(job, state.queue)}
  end

  # Starts queued jobs, oldest first, while there are free slots. A job whose
  # room already has a reply in progress waits without blocking other rooms.
  defp maybe_start_next(state) do
    busy = MapSet.new(Map.values(state.tasks), &job_room/1)

    with true <- map_size(state.tasks) < state.settings.parallel_replies,
         {job, rest} <- pop_ready(:queue.to_list(state.queue), busy, []) do
      endpoint_url = state.settings.endpoint_url

      task =
        Task.Supervisor.async_nolink(state.task_supervisor, fn ->
          generate(endpoint_url, job)
        end)

      %{state | queue: :queue.from_list(rest), tasks: Map.put(state.tasks, task.ref, job)}
      |> announce()
      |> maybe_start_next()
    else
      _no_free_slot_or_ready_job -> state
    end
  end

  defp pop_ready([], _busy, _skipped), do: nil

  defp pop_ready([job | jobs], busy, skipped) do
    if job_room(job) in busy,
      do: pop_ready(jobs, busy, [job | skipped]),
      else: {job, Enum.reverse(skipped, jobs)}
  end

  defp job_room({:persona, _persona, message}), do: message.room
  defp job_room({:character, room_name, _character}), do: room_name
  defp job_room({:regenerate, reply}), do: reply.room

  # Context: the messages before the mention, plus the mention itself.
  defp generate(endpoint_url, {:persona, persona, message}) do
    {history, _more?} =
      Chat.list_messages_page(message.room, message, persona.context_messages - 1)

    persona_reply(endpoint_url, persona, history ++ [message])
  end

  # The scene, cast and history are read when the turn starts, so the
  # character sees everything said while it waited in the queue. A player
  # may have put the character on meanwhile; then it is no longer the AI's.
  defp generate(endpoint_url, {:character, room_name, character}) do
    history = Chat.list_recent_messages(room_name, @scene_history)
    character_reply(endpoint_url, room_name, character, history)
  end

  # A reply is written again from what was said before it.
  defp generate(endpoint_url, {:regenerate, %{persona_id: id} = reply}) when is_integer(id) do
    case Assistant.get_persona(id) do
      nil ->
        {:error, :no_persona}

      persona ->
        {history, _more?} = Chat.list_messages_page(reply.room, reply, persona.context_messages)
        persona_reply(endpoint_url, persona, history)
    end
  end

  defp generate(endpoint_url, {:regenerate, %{character_id: id} = reply}) do
    {history, _more?} = Chat.list_messages_page(reply.room, reply, @scene_history)
    character_reply(endpoint_url, reply.room, %{id: id}, history)
  end

  defp persona_reply(endpoint_url, persona, history) do
    prompt = Assistant.build_prompt(persona, history, worn_characters(history))

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

  defp character_reply(endpoint_url, room_name, character, history) do
    with %{} = room <- Rooms.get_room(room_name) || {:error, :no_scene},
         cast = Rooms.list_ai_cast(room),
         %{} = character <- Enum.find(cast, &(&1.id == character.id)) || {:error, :not_cast},
         worn = worn_characters(history),
         template = Assistant.get_prompt_template(room.prompt_template_id),
         prompt =
           ScenePrompt.build(room, character, cast, history, worn, template && template.body),
         {:ok, text} <-
           LLM.impl().chat(endpoint_url, prompt,
             max_tokens: @scene_max_tokens,
             temperature: @scene_temperature
           ) do
      case ScenePrompt.clean(text, character, other_names(character, cast, history, worn)) do
        nil -> {:error, :empty_reply}
        reply -> {:ok, reply}
      end
    end
  end

  # The characters players wore when writing their messages.
  defp worn_characters(history) do
    ids = for %{from_assistant: false, character_id: id} <- history, is_integer(id), do: id
    Map.new(Characters.list_characters_by_ids(Enum.uniq(ids)), &{&1.id, &1})
  end

  defp other_names(character, cast, history, worn) do
    for(other <- cast, other.id != character.id, do: other.name) ++
      for(%{name: name} <- Map.values(worn), name != character.name, do: name) ++
      for(
        message <- history,
        message.username != character.name,
        uniq: true,
        do: message.username
      )
  end

  defp post_reply({:ok, reply}, {:persona, persona, message}) do
    Chat.create_assistant_message(message.room, persona.name, reply, persona_id: persona.id)
  end

  defp post_reply({:error, reason}, {:persona, persona, message}) do
    Logger.warning("Assistant #{persona.name} could not answer: #{inspect(reason)}")
    Chat.create_assistant_message(message.room, persona.name, @apology, persona_id: persona.id)
  end

  defp post_reply({:ok, reply}, {:character, room_name, character}) do
    Chat.create_character_message(room_name, character.name, reply, character.id)
  end

  # An out-of-character apology would break the scene; the turn is skipped.
  defp post_reply({:error, reason}, {:character, room_name, character}) do
    Logger.warning("#{character.name} could not answer in #{room_name}: #{inspect(reason)}")
  end

  defp post_reply({:ok, text}, {:regenerate, reply}), do: Chat.update_reply(reply, text)

  # The old text is announced again, so clients stop waiting for a new one.
  defp post_reply({:error, reason}, {:regenerate, reply}) do
    Logger.warning("#{reply.username} could not regenerate a reply: #{inspect(reason)}")
    Chat.update_reply(reply, reply.body)
  end

  ## Status

  # Announces every room/speaker pair that is online, and takes pairs that
  # were online before but no longer are (persona or character removed,
  # renamed, moved or assistant disabled) offline.
  defp announce(state) do
    online = if state.settings.enabled, do: online_speakers(state), else: %{}

    typing =
      MapSet.new(Map.values(state.tasks), fn
        {:persona, persona, message} -> {message.room, persona.name}
        {:character, room_name, character} -> {room_name, character.name}
        {:regenerate, reply} -> {reply.room, reply.username}
      end)

    for {{room, _name} = pair, speaker} <- online do
      broadcast_status(room, speaker, %{online: true, typing: pair in typing})
    end

    for {room, name} <- MapSet.difference(state.announced, MapSet.new(Map.keys(online))) do
      broadcast_status(room, %{name: name}, %{online: false, typing: false})
    end

    %{state | announced: MapSet.new(Map.keys(online))}
  end

  # {room, name} => speaker, for every persona and cast character on stage.
  defp online_speakers(state) do
    personas =
      for p <- state.personas, room <- p.rooms do
        {{room, p.name}, %{name: p.name, avatar_id: p.avatar_id, persona_id: p.id}}
      end

    characters =
      for {room, %{cast: cast}} <- state.scenes, c <- cast do
        {{room, c.name}, %{name: c.name, avatar_id: c.avatar_id, character_id: c.id}}
      end

    Map.new(personas ++ characters)
  end

  defp broadcast_status(room, speaker, flags) do
    status = %{
      room: room,
      name: speaker.name,
      persona_id: speaker[:persona_id],
      character_id: speaker[:character_id],
      avatar_id: speaker[:avatar_id]
    }

    Assistant.broadcast({:assistant_status, Map.merge(status, flags)})
  end
end
