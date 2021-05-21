alias Lib.Matrix.Server

defmodule Karma do
  use Task, restart: :permanent
  require Logger

  @html_matcher ~r/<a\shref=\"https:\/\/.*\/#\/(?<id>.*)\">(?<name>.*)<\/a>/

  def start_link(arg) do
    Task.start_link(__MODULE__, :run, [arg])
  end

  def run(arg) do
    Server.wait_for_server()

    Server.subscribe()

    work()
  end

  defp work() do
    # TODO: send to a worker, so multiple can be worked on at the same time
    receive do
      {:send_sync, sync} when sync != nil -> parse(sync)
      {:send_sync, _sync} -> nil
    end

    work()
  end

  defp parse(tesla) when tesla != nil do
    # IO.inspect(tesla.body)
    tesla = tesla.body["rooms"]["join"]

    tesla =
      tesla
      |> Enum.into([])

    parse_inner(tesla)
  end

  defp parse_inner(data) when data == [] do
  end

  defp parse_inner([{name, data} | tail]) when is_binary(name) and is_map(data) do
    parse_event(data["timeline"]["events"], resolve_name(name))

    parse_inner(tail)
  end

  defp parse_event([event | tail], room) when is_map(event) do
    case event["type"] do
      "m.room.message" -> parse_message(event["content"], room)
      _ -> Logger.debug("unknown type: #{event["type"]}, room: #{inspect(room)}")
    end

    parse_event(tail, room)
  end

  defp parse_event(_, _), do: nil

  defp parse_message(content, room) when is_map(content) do
    {name, _id} = room
    Logger.debug("parsing message '#{content["body"]}' from room #{name}")
    IO.inspect(content)

    # if String.ends_with?(content["body"], "++")
    cond do
      String.ends_with?(content["body"], "++") -> parse_message(content, room, true)
      String.ends_with?(content["body"], "--") -> parse_message(content, room, false)
      true -> nil
    end

    # TODO: send read message
  end

  defp parse_message(content, room, action) when is_map(content) do
    case content["format"] do
      "org.matrix.custom.html" -> parse_message(:html, content, room, action)
      nil -> parse_message(:plain, content, room, action)
      _ -> Logger.warn("cannot parse message format")
    end
  end

  defp parse_message(:html, content, room, action) when is_map(content) do
    {_room_name, room_id} = room
    html = content["formatted_body"]
    res = Regex.named_captures(@html_matcher, html)
    karma = Karma.StoreAdapter.store(action, {res["name"], res["id"]}, room)
    Logger.debug("#{res["name"]} has a karma of #{karma}")

    Server.send_reply(
      room_id,
      "#{res["name"]} has #{karma} points",
      "<a href=\"https://matrix.to/#/#{res["id"]}\">#{res["name"]}</a> has #{karma} points"
    )
  end

  defp parse_message(:plain, content, _room, _action) when is_map(content) do
    Logger.warn("implement non html parsing")
  end

  defp parse_message_trim(content, split) do
    message = content["body"]

    if String.contains?(message, ":") do
      [name | _] = String.split(message, ":")
      name
    else
      [message | _] = String.split(content["body"], split)
      message
    end
  end

  defp resolve_name(id) when is_binary(id) do
    {Lib.Matrix.Server.get_rooms()[id], id}
  end
end
