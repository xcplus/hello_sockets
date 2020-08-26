defmodule HelloSocketsWeb.PingChannel do
  use Phoenix.Channel

  # 拦截request_ping事件
  intercept ["request_ping"]

  def join(_topic, _payload, socket) do
    {:ok, socket}
  end

  def handle_in("ping", %{"ack_phrase" => ack_phrase}, socket) do
    {:reply, {:ok, %{ping: ack_phrase}}, socket}
  end

  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{ping: "pong"}}, socket}
  end

  def handle_in("ping:" <> phrase, _payload, socket ) do
    {:reply, {:ok, %{ping: phrase}}, socket}
  end

  # 什么都不做
  def handle_in("pong", _payload, socket) do
    {:noreply, socket}
  end

  # 停止Channel
  def handle_in("pang", _payload, socket) do
    {:stop, :shutdown, {:ok, %{msg: "shutting down"}}, socket}
  end

  def handle_out("request_ping", payload, socket) do
    push(socket, "send_ping", Map.put(payload, "from_node", Node.self()))
    {:noreply, socket}
  end

  def handle_in("param_ping", %{"error" => true}, socket) do
    {:reply, {:error, %{reason: "You asked for this!"}}, socket}
  end

  def handle_in("param_ping", payload, socket) do
    {:reply, {:ok, payload}, socket}
  end
end