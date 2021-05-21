alias Lib.Matrix.Server
alias Lib.Matrix.Scraper

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
      "m.reaction" -> parse_reaction(event, room)
      # "m.room.redaction" -> parse_redaction(event, room)
      _ -> Logger.debug("unknown type: #{event["type"]}, room: #{inspect(room)}")
    end

    parse_event(tail, room)
  end

  defp parse_event(_, _), do: nil

  defp parse_message(content, room) when is_map(content) do
    {name, _id} = room
    Logger.debug("parsing message '#{content["body"]}' from room #{name}")

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

    Server.send_karma(karma, res["name"], res["id"], room_id)
  end

  defp parse_message(:plain, content, _room, _action) when is_map(content) do
    Logger.warn("implement non html parsing")
  end

  defp parse_reaction(content, room) when is_map(content) do
    id = content["content"]["m.relates_to"]["event_id"]
    key = content["content"]["m.relates_to"]["key"]

    action =
      if key == "👍️" do
        :plus
      else
        if key == "👎️" do
          :minus
        end

        :none
      end

    sender = content["sender"]

    if action != :none do
      parse_reaction(action == :plus, id, sender, room)
    else
      nil
    end
  end

  def parse_reaction(action, reaction_id, reaction_sender, room)
      when is_boolean(action) and is_binary(reaction_id) do
    {_room_name, room_id} = room

    event =
      case Scraper.get_room_event(room_id, reaction_id, Server.get_token(), Server.get_server()) do
        {:ok, event} -> event
        _ -> :error
      end

    if event != :error do
      event_sender = event["sender"]

      sender_name =
        case Server.resolve_name(event_sender) do
          {:ok, name} -> name
          _ -> "ERROR"
        end

      if reaction_sender == event_sender do
        Server.self_credit(sender_name, event_sender, room_id)
      else
        karma = Karma.StoreAdapter.store(action, {"todo", event_sender}, room)
        Server.send_karma(karma, sender_name, event_sender, room_id)
      end
    end
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
