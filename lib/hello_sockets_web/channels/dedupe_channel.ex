defmodule HelloSocketsWeb.DedupeChannel do
  use Phoenix.Channel

  # 拦截number事件
  # 我们拦截了事件“ number”，并为接收到该事件定义了handle_out回调。 我们的handle_out函数与正常函数不同，因为我们不调用push函数。 我们之所以这样做，是因为当我们拦截消息时，没有什么要求我们将消息推送给客户端。
  intercept ["number"]

  def join(_topic, _payload, socket) do
    {:ok, socket}
  end

  def handle_out("number", %{number: number}, socket) do
    buffer = Map.get(socket.assigns, :buffer, [])
    next_buffer = [number | buffer]

    next_socket = socket
      |> assign(:buffer, next_buffer)
      |> enqueue_send_buffer()

    {:noreply, next_socket}
  end

  defp enqueue_send_buffer(socket = %{assigns: %{awaiting_buffer?: true}}), do: socket
  defp enqueue_send_buffer(socket) do
    Process.send_after(self(), :send_buffer, 1_000)
    assign(socket, :awaiting_buffer?, true)
  end

  def handle_info(:send_buffer, socket = %{assigns: %{buffer: buffer}}) do
    buffer
    |> Enum.reverse()
    |> Enum.uniq()
    |> Enum.map(&push(socket, "number", %{value: &1}))

    next_socket = 
      socket
      |> assign(:buffer, [])
      |> assign(:awaiting_buffer?, false)

    {:noreply, next_socket}
  end

  def broadcast(numbers, times) do
    Enum.each(1..times, fn _ -> 
      Enum.each(numbers, fn number -> 
        HelloSocketsWeb.Endpoint.broadcast!("dupe", "number", %{number: number})
      end)
    end)
  end
end