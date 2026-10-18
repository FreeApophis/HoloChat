defmodule HoloChat.Assistant.Server do
  @moduledoc """
  The assistant idling in a chat room (the lobby by default).

  It listens to the room and, while enabled, answers messages that mention
  it as `@Name`. Mentions are queued and answered one at a time, because a
  local model server generates one reply at a time anyway. Generation runs
  in a task so the server stays responsive.

  Status changes are broadcast as `{:assistant_status, status}` on the
  assistant topic (see `HoloChat.Assistant.subscribe/0`), where `status` is
  `%{room: room, name: name, online: boolean, typing: boolean}`. Sending
  `:assistant_status_request` on that topic makes servers re-announce.
  """

  use GenServer

  require Logger

  alias HoloChat.{Assistant, Chat}
  alias HoloChat.Assistant.LLM

  @max_queue 5
  @apology "Sorry, I can't answer right now. Please try again later."

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    room = Keyword.get(opts, :room, "lobby")
    Chat.subscribe(room)
    Assistant.subscribe()

    state = %{
      room: room,
      settings: Assistant.get_settings(),
      queue: :queue.new(),
      task: nil,
      task_supervisor: Keyword.get(opts, :task_supervisor, HoloChat.Assistant.TaskSupervisor)
    }

    {:ok, announce(state)}
  end

  @impl true
  def handle_info({:new_message, message}, state) do
    if wants_to_answer?(message, state) do
      {:noreply, state |> enqueue(message) |> maybe_start_next()}
    else
      {:noreply, state}
    end
  end

  def handle_info({:assistant_settings_changed, settings}, state) do
    {:noreply, announce(%{state | settings: settings})}
  end

  def handle_info(:assistant_status_request, state), do: {:noreply, announce(state)}
  def handle_info({:assistant_status, _status}, state), do: {:noreply, state}

  def handle_info({ref, result}, %{task: {ref, _message}} = state) do
    Process.demonitor(ref, [:flush])
    post_reply(result, state)
    {:noreply, %{state | task: nil} |> announce() |> maybe_start_next()}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: {ref, _message}} = state) do
    post_reply({:error, {:crashed, reason}}, state)
    {:noreply, %{state | task: nil} |> announce() |> maybe_start_next()}
  end

  defp wants_to_answer?(message, %{settings: settings, queue: queue}) do
    settings.enabled and not message.from_assistant and
      Assistant.mentioned?(settings.name, message.body) and
      :queue.len(queue) < @max_queue
  end

  defp enqueue(state, message), do: %{state | queue: :queue.in(message, state.queue)}

  defp maybe_start_next(%{task: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, message}, queue} ->
        settings = state.settings

        task =
          Task.Supervisor.async_nolink(state.task_supervisor, fn ->
            generate(settings, message)
          end)

        announce(%{state | queue: queue, task: {task.ref, message}})

      {:empty, _queue} ->
        state
    end
  end

  defp maybe_start_next(state), do: state

  # Context: the messages before the mention, plus the mention itself.
  defp generate(settings, message) do
    {history, _more?} =
      Chat.list_messages_page(message.room, message, settings.context_messages - 1)

    prompt = Assistant.build_prompt(settings, history ++ [message])

    with {:ok, text} <-
           LLM.impl().chat(settings.endpoint_url, prompt,
             max_tokens: settings.max_tokens,
             temperature: settings.temperature
           ) do
      case Assistant.clean_reply(settings.name, text) do
        nil -> {:error, :empty_reply}
        reply -> {:ok, reply}
      end
    end
  end

  defp post_reply({:ok, reply}, state) do
    Chat.create_assistant_message(state.room, state.settings.name, reply)
  end

  defp post_reply({:error, reason}, state) do
    Logger.warning("Assistant could not answer: #{inspect(reason)}")
    Chat.create_assistant_message(state.room, state.settings.name, @apology)
  end

  defp announce(state) do
    Assistant.broadcast(
      {:assistant_status,
       %{
         room: state.room,
         name: state.settings.name,
         online: state.settings.enabled,
         typing: state.task != nil
       }}
    )

    state
  end
end
