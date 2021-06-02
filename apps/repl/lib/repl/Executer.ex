defmodule Repl.Executor do
  require Logger

  def run(:err, _args, room, _system, event) do
    {_room_name, room_id} = room
    {plain, html} = create_response_error(event, room_id)
    Lib.Matrix.Server.send_reply(room_id, plain, html)
  end

  def run(expression, args, room, system, event) do
    {_room_name, room_id} = room

    task = shedule_task(expression, args, system)
    {log, code} = Task.await(task)

    case code do
      0 ->
        Lib.Matrix.Server.send_reply(room_id, log)

      _ ->
        Lib.Matrix.Server.send_reply(room_id, "failed\n" <> log)
    end

    # Lib.Matrix.Server.send_reply(room_id, "I can't handle this yet:\n" <> expression)
  end

  defp shedule_task(expression, args, system) do
    Logger.warn("Ipmlement scheduling on #{system}")

    Task.Supervisor.async(Repl.Spawner.TaskSupervisor, fn -> execute(expression, args) end,
      timeout: 30000
    )
  end

  defp execute(expression, args) do
    filename = create_job(expression)

    port =
      Port.open(
        {:spawn, "nix-instantiate --eval '<eval-file>' -I eval-file=#{filename} #{args} 2>&1"},
        [:binary, :exit_status]
      )

    {log, code} = collect_log()
    File.rm(filename)
    {log, code}
  end

  defp create_job(expression) do
    dir =
      case :os.type() do
        {:unix, :darwin} -> "/private/tmp/not-nix-repl/"
        _ -> "/tmp/not-nix-repl/"
      end

    File.mkdir(dir)

    filename = dir <> UUID.uuid1() <> ".nix"
    {:ok, file} = File.open(filename, [:write])
    IO.binwrite(file, expression)
    filename
  end

  defp collect_log() do
    receive do
      {_port, {:data, line}} ->
        # IO.puts("got line: #{line}")
        {new_line, status} = collect_log()
        {line <> new_line, status}

      # TODO: add to something
      {_port, {:exit_status, c}} ->
        # IO.puts("exited: #{inspect c}")
        {"", c}
    end
  end

  defp create_response_error(event, room) do
    plain = "> <#{event["sender"]}> #{event["content"]["body"]}\nError in nix expression"
    # <mx-reply><blockquote><a
    # href=\"https://matrix.to/#/!dwDnfJZEPulpEHXXHa:petabyte.dev/$vSvbCo0f0eWJL0lpU-NO_W_3TbV9Br-C-ksMl4J9-kw?via=petabyte.dev\">
    # In reply to</a> <a href=\"https://matrix.to/#/@milan:petabyte.dev\">@milan:petabyte.dev</a><br><pre>
    # <code class=\"language-nix\">builtins.getFlake \"git+https://github.com/torvalds/linux\"\n</code>
    # </pre>\n</blockquote></mx-reply>denied
    # todo: via
    html = "<mx-reply>
      <blockquote>
        <a href=\"https://matrix.to/#/#{room}/#{event["event_id"]}?via=petabyte.dev\">In reply to</a>
        <a href=\"https://matrix.to/#/#{event["sender"]}\">#{event["sender"]}</a>
        #{event["content"]["formatted_body"]}
      </blockquote></mx-reply>
      Error in nix expression"
    # TODO: m.relate
    {plain, html}
  end
end
