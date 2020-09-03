# WebSocket 链接请求流程：

  ```ruby
  curl -i "http://localhost:4000/socket/websocket?vsn=2.0.0"
  ```

  1. 向WebSocket端点发起GET HTTP（S）连接请求
  2. 从服务器接收到101或错误
  3. 如果收到101，则将协议升级到WebSocket
  4. 通过WebSocket连接发送/接收帧

注：客户端管理心跳而不是服务器，这很有用。 如果客户端的ping请求检测到连接问题，则客户端可以快速尝试重新连接并重新建立连接。 如果服务器负责向客户端发送ping，则服务器知道连接问题，但无法与客户端建立新连接。 这会使客户处于较长时间的脱节状态。

# 长轮询

HTTP长轮询[17]是一种使用标准HTTP以便将数据异步发送到客户端的技术。 这符合可以发送（长轮询响应）和从客户端接收（客户端请求）数据的实时通信层的要求。 长轮询是WebSockets最常用的前身，比它早几年。 这意味着该技术尽管有缺点，却非常稳定。

长轮询的请求流程：
  1. 客户端向服务器发起HTTP请求。
  2. 服务器不响应请求，而是保持打开状态。 服务器收到新数据或时间过长时将做出响应。
  3. 服务器将完整的响应发送给客户端。 此时，客户端知道了来自服务器的实时数据。
  4. 只要需要实时通信，客户端就会循环此流程。

长轮询流程的关键部分是，客户端与服务器的连接将保持打开状态，直到收到新数据为止。 这样一来，数据就可以立即推送到连接的客户端。 长轮询是一种用于实时通信的可行技术，但是它面临的挑战使WebSockets显然是我们应用程序的更好选择。

### 长轮询
  #### 缺点
    1. 每个长轮询请求都会处理请求标头。 这可能会大大增加服务器需要处理的传输字节数。 这并非最佳效果
    2. 当使用不良网络时，消息延迟可能会很高。 丢弃的数据包和数据传输时间会使延迟大大增加，因为必须重新建立多个连接才能重新建立长轮询连接。 这会影响应用程序的实时感。

  #### 优点
    1. 长轮询连接可以在多个服务器之间轻松实现负载平衡，因为经常建立连接。如果连接寿命长，WebSockets可能很难进行负载平衡，因为不会发生重新连接以更改客户端连接到哪个服务器。
    2. 可以透明地利用协议的改进，例如HTTP的未来版本。 Google是互联网协议的创新者，它利用一种长期轮询的自定义形式来为某些实时应用程序提供支持。

# Phoenix
```
                                                                  +----------------+
                                                     +--Topic X-->| Mobile Client  |
                                                     |            +----------------+
                              +-------------------+  |
+----------------+            |                   |  |            +----------------+
| Browser Client |--Topic X-->| Phoenix Server(s) |--+--Topic X-->| Desktop Client |
+----------------+            |                   |  |            +----------------+
                              +-------------------+  |
                                                     |            +----------------+
                                                     +--Topic X-->|   IoT Client   |
                                                                  +----------------+
```

# Phoenix Channels

客户端通过直接连接到管理连接的OTP进程，通过WebSocket等传输机制连接到服务器。 此过程将某些操作（例如，接受还是拒绝连接请求）委派给实现Phoenix.Socket行为的应用程序代码。

使用Phoenix.Socket的模块可以将客户端请求的主题路由到提供的Phoenix.Channel实现模块。 Channel模块针对用户连接到的每个不同主题启动一个单独的进程。 Channel像传输进程一样，永远不会在不同的连接之间共享。

```
----------------         -----------------       ---------------------------
|client request|   --->  | Phoenix.Socket|  -->  |扩展了Phoenix.Channel的模块| 
----------------         -----------------       ---------------------------

    -------------
--> |  process  |
    -------------
```

### Sockets

Sockets 构成了Phoenix实时通信的基础。 Socket是实现Phoenix.Socket.Transport行为的模块，但是我们将使用称为Phoenix.Socket的特定实现。 您很可能会在应用程序中使用Phoenix.Socket，因为它以遵循最佳实践的方式实现了WebSocket和长轮询。 （如果您需要一个罕见的自定义传输层，那么您确实可以实现自己的Socket.Transport。）

我们只需要实现一些功能即可创建功能性的Socket实现, 回调函数connect/3和id/1提供了我们应用程序套接字的模板。

connect/3 可以用于认证用户
id/1 识别当前链接的客户端,用于追踪Socket或者想要断开链接

### Channels

是我们应用程序逻辑的实时入口点，并且是大多数应用程序的请求处理代码所在的位置。 Channel具有多种职责来启用实时应用程序：

1. 接受或拒绝加入请求
2. 处理来自客户端的消息
3. 处理来自PubSub的消息
4. 将消息推送到客户端

Socket 的职责包括连接处理和将请求路由到正确的 Channel。 Channel 的职责涉及处理来自客户的请求并将数据发送到客户。 Channel 类似于MVC（模型-视图-控制器）设计模式中的控制器


### Topics
是字符串标识符，当套接字接收到“phx_join”消息时，该标识符用于连接到正确的Channel。 它们是在Socket模块中定义的，就像我们之前在UserSocket示例中看到的那样。


### PubSub
Phoenix.PubSub（发布者/订阅者）在我们的实时应用程序中为Topic订阅和消息广播提供支持。 Channel在内部使用PubSub，因此我们很少会直接与其进行交互。 但是，了解PubSub很有用，因为我们需要为我们的应用程序正确配置它，以确保性能和通信可用性。

PubSub链接在本地节点和所有连接的远程节点之间。 这使PubSub可以在整个群集中广播消息。 当客户端处于连接到群集节点A的消息来自群集节点B的情况下，远程消息广播非常重要。 PubSub开箱即用为我们处理此问题，但我们确实需要确保节点之间可以互相通信。 PubSub随附了pg2适配器。 还有一个Redis PubSub适配器，它允许使用PubSub而无需将节点群集在一起。

当我们调用HelloSocketsWeb.Endpoint.broadcast/3函数时，将使用PubSub

# 发送和接受消息

### Phoenix 的消息结构

+ Join Ref - 唯一的字符串，与客户端连接到Channel时提供的内容匹配。 这用于帮助防止来自客户端的重复频道订阅。 实际上，这个数字在每次加入频道时都会增加
+ Message Ref - 客户端在每条消息上提供的唯一字符串。 这用于允许发送答复以响应客户消息。 实际上，这是一个数字，每当客户发送一条消息时，该数字就会增加
+ Topic - Channel 对应的 Topic
+ Event - 标识消息的字符串， Channel 实现可以使用模式匹配轻松处理不同事件
+ Payload - 一个 JSON 编码的映射（字符串），包含消息的数据内容。 Channel 实现可以在解码后的Map上使用模式匹配来处理事件的不同情况

### 接受来自客户端的消息

当客户将消息发送到Channel时，传输过程会接收到该消息并将其委托给Socket的handle_in/2回调。 Socket将解码的Message结构发送到正确的Channel进程，并处理任何错误，例如Topic不匹配。 Phoenix.Channel.Server进程通过委派给关联的Channel实现的handle_in/3回调来处理发送的消息。 这对我们来说是透明的，这意味着我们只需要关心客户端发送消息以及我们Channel的handle_in/3回调处理消息。

### 其他响应类型

我们还有其他方法可以处理传入事件，而不是回复客户({:reply, payload, socket} | {:reply, socket})。 让我们看一下两种不同的回应方式：什么都不做({:noreply, socket})或停止频道({:stop, :shutdown, {:ok, %{....}}, socket})。

### 发送消息到客户端

如果不需要自定义有效负载，则最好不要编写拦截事件，因为每个推送的消息将由其自身进行编码，每个订阅的Channel最多编码一次，而不是一次推送到所有订阅的Channel。 这将降低具有许多订户的系统的性能。

# Channel 客户端(频道客户端)

### 官方Javascirpt客户端

任何Channel客户都有一些关键职责，为了使所有行为都能按预期进行，应遵循以下几个关键职责：
- 连接到服务器并使用心跳保持连接
- 加入请求的Topic
- 将消息推送到Topic并可以选择处理响应
- 接收来自Topic的消息
- 妥善处理断开连接和其他错误； 尝试尽可能保持连接


# 限制套接字和通道访问 Restrict Socket and Channel Access

注：Phoenix提供了两个不同的入口，可以在其中添加访问限制。身份验证在Socket的Socket.connect/3函数中处理，而授权在Channel的Channel.join/3函数中处理。您将同时使用两种限制来完全保护您的实时应用程序。

### 给Socket添加身份验证

心跳和附加连接意味着，许多空闲Channel的成本低于许多空闲Socket的成本.

在决定是添加新的Socket还是添加新的Channel Topic时使用现有的Socket时，应首先考虑应用程序的身份验证需求。当您编写一个具有单独的实时功能或供用户和管理员使用的页面的系统时，您将添加一个新的Socket。这是因为用户将无法连接到管理员特定的功能，因此应拒绝连接到Socket。像这样分开Socket身份验证会导致系统中更简单的代码。当身份验证需求相同时，您将添加到现有Socket。

通常，将多个Channel与单个Socket一起使用。如果您的应用程序在应用程序的不同部分之间具有不同的身份验证需求，请使用多个Socket。这种方法导致系统架构具有最低的资源使用率。

# 第五章

### Channel 订阅管理
### 保持关键数据有效
### 消息传递

## 使用群集中的 Channel
Elixir使连接BEAM节点的集群（Erlang / Elixir的运行时系统的单个实例）变得非常容易。 但是，我们必须确保构建的应用程序能够在多个节点上正常运行。 Phoenix Channels 为我们处理了很多这样的事情，这是因为PubSub被用于所有消息广播。

### 连接本地群集
让我们直接启动一个本地Elixir节点（我们的应用程序实例），其名称为：
```elixir
$ iex --name server@127.0.0.1 -S mix phx.server
```
我们使用--name开关为节点指定名称。 您可以在输入条目行上看到名称； 我们的位于server@127.0.0.1。 让我们开始第二个节点：
```elixir
$ iex --name remote@127.0.0.1 -S mix
```

我们通过启动mix而不是mix phx.server，来启动了第二个不运行Web服务器的节点。 我们使用了不同的名称remote@127.0.0.1，这使我们可以在同一主机域上运行两个节点。 您可以使用Node.list/0查看当前连接的所有节点，并查看没有节点。 我们纠正一下：
```elixir
iex(remote@127.0.0.1)1> Node.list()
[]
iex(remote@127.0.0.1)2> Node.connect(:"server@127.0.0.1")
true
iex(remote@127.0.0.1)3> Node.list()
[:"server@127.0.0.1"]
```
我们从远程节点运行Node.connect/1以连接到服务器节点。 这将创建一个连接的节点集群，可以通过再次运行Node.list/0进行验证。 尝试在服务器节点上运行Node.list/0，您将看到它包含远程节点名称。

我们要做的就是利用pg2支持的Phoenix PubSub的标准分发策略。 我们可以从无法服务Socket的远程节点广播一条消息，并在连接到主服务器上Socket的客户端上看到该消息。 让我们尝试一下：

首先，连接到ping主题以建立连接。

```elixir
$ wscat -c "ws://localhost:4000/socket/websocket?vsn=2.0.0"
Connected (press CTRL+C to quit)
> ["1", "1", "ping", "phx_join", {}]
< ["1","1","ping","phx_reply",{"response":{},"status":"ok"}]
>
```

下一步从remote 服务器中广播消息
```elixir
iex(remote@127.0.0.1)5> HelloSocketsWeb.Endpoint.broadcast("ping", "request_ping", %{})
:ok
```
然后会看到ping请求返回到客户端：
```elixir
< [null,null,"ping","send_ping",{"from_node":"server@127.0.0.1"}]
```

向客户端发送消息的节点是server@127.0.0.1，但我们从remote@127.0.0.1发送了广播。 这意味着该消息已分布在整个群集中，并被我们服务器节点上的PingChannel拦截。

该演示演示了我们可以在集群中的任何地方发出一条消息，并且该消息会将其发送给客户端。 这对于在多台服务器上运行的正确运行的应用程序至关重要，我们可以通过使用Phoenix PubSub以非常低的成本获得它。

实际上，我们的remote node将为套接字连接提供服务，并且整个系统将放置在平衡不同服务器之间连接的工具之后。 您可以通过在应用程序配置中更改HTTP端口并使用wscat连接到新端口来在本地进行模拟。
```elixir
$ ​​PORT=4001​​ ​​iex​​ ​​--name​​ ​​remote@127.0.0.1​​ ​​-S​​ ​​mix​​ ​​phx.server​
​[info] Running Web.Endpoint with cowboy 2.6.3 at 0.0.0.0:4001 (http)
​[info] Access Web.Endpoint at http://localhost:4001
​iex(remote@127.0.0.1)1>
```
您可以尝试在不同节点之间发送消息，以确认它们是在任一方向上传递的。 您将以（到目前为止）未编写的内容更详细地了解集群部署。

频道分发功能非常强大，易于使用。 但是，接下来会遇到一些挑战。

### 使用分布式 Channel 的挑战
分发应用的几个挑战：
. 我们无法确定我们在任何给定时间都对远程节点的状态有完全准确的了解。 我们可以使用技术和算法来减少不确定性，但不能完全消除不确定性。
. 消息可能无法以我们期望的速度或根本没有被传输到远程节点。 完全丢弃消息的情况很少见，但是消息延迟更为普遍。
. 编写高质量的测试变得更加复杂，因为我们必须启动更复杂的场景来完全测试我们的代码。 可以在Elixir中编写测试，以启动本地集群以模拟不同的环境。
. 我们的客户端可能会与节点断开连接，并最终处于具有不同内部状态的其他节点上。 我们必须通过拥有任何节点都可以引用的中心真理来源来适应这种情况。 这是最常见的共享数据库。

## 自定义channel行为
Phoenix频道由GenServer支持，使其可以接收消息并存储状态。 我们可以利用Channels的此属性，以便在每个连接级别上自定义Channel的行为。 这样，我们就可以建立标准消息广播无法实现（或将变得更加复杂）的流程，而标准消息广播无法轻松地将消息发送给单个客户端。

由于套接字的过程结构，我们无法自定义套接字的行为。 通过逐步介绍使用Phoenix.Socket.assign/3和消息发送的几种不同模式，我们将把注意力集中在这些示例的通道级别自定义上。

## 发送定期消息
有时我们需要定期向客户端发送数据。 一个用例是每隔几分钟刷新一次身份验证令牌，以确保客户端始终具有有效的令牌。 这很有用，因为如果所有客户端同时请求令牌，则可能使服务器不堪重负。

我们的频道将使用Process.send_after/3每五秒钟向自己发送一条消息。 该流程将在Channel进程初始化时启动，但是也可以响应于客户端启动的消息，在我们的handle_in回调中启动该流程。

首先，向AuthSocket模块添加新的"recurring"渠道路由。
```elixir
channel "recurring", HelloSocketsWeb.RecurringChannel
```

### 重复删除外发邮件
防止重复的传出消息是自定义渠道的一项重要工作。这个问题的解决方案必须尽可能靠近客户端，因为这样我们就可以确定已将哪些消息发送到特定客户端。通道是我们在单个客户端和服务器之间控制的最低级别的过程。这使它们成为我们完成这项任务的理想地点。

在最后一个示例中，我们使用Socket.assigns存储与套接字相关的状态。在此示例中，我们将使用Socket.assigns存储与我们的频道相关的状态。

我们可以将所需的任何内容放入Socket.assigns。我们添加到Socket.assigns中的任何数据仅适用于我们的Channel进程，其他Channel进程甚至使用相同Socket的Channel都不会看到。起初这可能会造成混淆，但是当您认为Elixir具有功能且通常没有副作用时，这是有道理的。如果我们修改Channel进程的状态，则系统中的其他进程不会受到影响。

# Chapter 6 避免性能下降
### 未知的应用程序运行状况(Unknown application health)
### 有限的通道吞吐量(Limited Channel throughput)
通道使用服务器上的单个进程来处理传入和传出请求。 如果我们不小心，可能会限制我们的应用程序，以便长时间运行的请求会阻止Channel处理。 我们将通过内置的Phoenix函数解决此问题。
### 意外数据管道(Unintentional data pipeline)
我们可以建立一条管道，以有效地将数据从服务器转移到用户。 我们应该有意识地进行数据管道设计，以便我们了解解决方案的功能和局限性。 我们将使用GenStage建立可用于生产的数据管道。

#### 测量类型
了解我们的应用程序是否正常运行的最佳方法是将检测放置在尽可能多的不同事件和系统操作上。
这里有一些简单但有效的方法可以用来衡量事物：

. 计数发生次数-操作发生的次数。 我们可以计算每次将消息推送到我们的频道的时间，也可以计算每次Socket连接失败的时间。
. 在某个时间点计数-我们系统组件在某个时刻的价值。 可以每隔几秒钟计算连接的套接字和通道的数量。 在许多测量工具中，通常将其称为量规。
. 操作时间-完成操作所需的时间。 我们可以测量事件生成后将事件推送到客户端所花费的时间。

每种测量类型在不同情况下都是有用的，没有一种类型优于其他类型。 将不同的度量组合到一个视图中（在您选择的可视化工具中）可以帮助查明问题。 例如，新连接的出现可能与存储消耗的增加相吻合。 所有这些都可能导致消息传递时间的增加。 这些测量中的每一个都会告诉您一些信息，但不能告诉您全部情况。 所有这些的组合有助于理解系统的压力。

通常会收集一些标识信息来收集度量。 至少每个度量都有一个名称和值，但是某些工具允许使用更多结构化的方式来指定其他数据，例如使用标签。 我们能够将其他元数据附加到我们的度量中，以帮助讲述应用程序的故事。 例如，共享的在线应用程序经常使用“租户”的概念来隔离客户的数据。 我们可以向所有指标添加一个tenant_id = XX标记，以从单个租户的角度了解当前系统的运行状况。

#### 使用StatsD收集测量
StatsD是一个聚合统计信息的守护程序；它会测量应用程序发送给它的度量，并将其汇总到其他收集统计信息的后端中。许多APM提供StatsD后端集成。这使StatsD成为收集测量值的理想选择。

除了StatsD之外，您还可以使用其他工具来收集测量值。 StatsD是常用的并且易于理解，因此我们将在本书中使用它。如果您有其他喜欢的工具，则应使用该工具。重要的是您要收集所有测量数据。

通过使用Statix库，很容易在Elixir中开始使用StatsD。该库具有简单的界面，其功能与StatsD测量类型相对应。在本书中，我们将使用Statix，以便在应用程序中捕获测量结果。

让我们使用Statix和本地StatsD服务器在我们的HelloSockets应用程序中捕获各种度量。 我们将使用伪造的StatsD服务器进行开发，该服务器只会将所有数据包记录到Elixir应用程序控制台中。
187
