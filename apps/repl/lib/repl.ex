alias Lib.Matrix.Server

defmodule Repl do
  use Task, restart: :permanent
  require Logger

  def start_link(arg) do
    Task.start_link(__MODULE__, :run, [arg])
  end

  def run(_arg) do
    Server.wait_for_server()
    Server.subscribe()

    work()
  end

  defp work() do
    receive do
      {:send_sync, sync} when sync != nil -> parse(sync)
      {:send_sync, _sync} -> nil
    end

    work()
  end

  defp parse(tesla) when tesla != nil do
    tesla =
      tesla.body["rooms"]["join"]
      |> Enum.map(&Task.Supervisor.start_child(Repl.TaskSupervisor, fn -> parse_inner(&1) end))

    # |> Enum.into([])

    # Task.Supervisor.async_stream_nolink(Repl.TaskSupervisor, tesla, fn v -> parse_inner(v) end,
    #  ordered: false, timeout: :infinity
    # )
    # |> Enum.reduce(0, fn _x, _y -> nil end)
  end

  defp parse_inner({name, data}) when is_binary(name) and is_map(data) do
    events = data["timeline"]["events"]
    name = resolve_name(name)

    # Task.Supervisor.async_stream_nolink(
    #  Repl.TaskSupervisor,
    #  events,
    #  fn v -> parse_event(v, name) end,
    #  ordered: false, timeout: :infinity
    # )
    # |> Enum.reduce(0, fn _x, _y -> nil end)
    events
    |> Enum.map(
      &Task.Supervisor.start_child(Repl.TaskSupervisor, fn -> parse_event(&1, name) end)
    )
  end

  defp parse_event(event, room) when is_map(event) do
    {room_name, room_id} = room

    if room_name != nil do
      case event["type"] do
        "m.room.message" -> parse_message(event["content"], room, event)
        _ -> Logger.debug("unknown type: #{event["type"]}, room: #{room_name}")
      end
    else
      Logger.debug("not parsing events for room #{room_id}")
    end
  end

  defp parse_message(content, room, event) when is_map(content) do
    {name, id} = room
    name = if name == "", do: id, else: name

    format = content["format"]

    if format == "org.matrix.custom.html" do
      {:ok, doc} = Floki.parse_document(content["formatted_body"])

      doc
      |> Floki.filter_out("mx-reply")
      |> Floki.find("code")
      |> Enum.map(&parse_code(&1, room, event))
    end
  end

  defp parse_code(code, room, event) do
    {_tag, attrs, content} = code
    {lang, system} = get_lang(attrs)

    if lang == :nix do
      content =
        content
        |> Enum.join("\n")
        |> String.trim()
        |> String.split("\n")
        |> Enum.map(&parse_code(&1))
        |> Repl.Spawner.compute(room, system, event)
    end
  end

  defp parse_code(line) do
    if String.contains?(line, "=") do
      [name | value] = String.split(line, "=", trim: true, parts: 2)
      name = String.trim(name)
      value = hd(value) |> String.trim()
      {:var, {name, value}}
    else
      {:code, line}
    end
  end

  defp get_lang([{"class", lang} | tail]) when is_binary(lang) do
    if String.starts_with?(lang, "language-") do
      [lang | attrs] = String.replace_leading(lang, "language-", "") |> String.split(",")
      lang = if lang == "nix", do: :nix

      system =
        if length(attrs) == 0 do
          Repl.Spawner.own_arch()
        else
          [system | _] = attrs
          system
        end

      {lang, system}
    else
      get_lang(tail)
    end
  end

  defp get_lang([_head | tail]) do
    get_lang(tail)
  end

  defp get_lang([]) do
    {nil, nil}
  end

  defp resolve_name(id) when is_binary(id) do
    {Lib.Matrix.Server.get_rooms()[id], id}
  end
end
