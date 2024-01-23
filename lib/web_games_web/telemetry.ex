defmodule WebGamesWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      # Add reporters as children of your supervision tree.
    ]

    # Eventually add the rest
    reported_metrics = GamePlatform.Telemetry.metrics() # ++ metrics()

    reporter = case Application.get_env(:web_games, :telemetry)[:reporter_type] do
      :none -> []
      :console -> [{Telemetry.Metrics.ConsoleReporter, metrics: reported_metrics}]
      :statsd -> configure_statsd_reporter(reported_metrics)
      _ -> []
    end

    Supervisor.init(children ++ reporter, strategy: :one_for_one)
  end

  defp configure_statsd_reporter(metrics) do
    host = Application.get_env(:web_games, :telemetry_statsd)[:host]
    port = Application.get_env(:web_games, :telemetry_statsd)[:port]
    case Application.get_env(:web_games, :telemetry_statsd)[:socket] do
      nil -> [{TelemetryMetricsStatsd, metrics: metrics, host: host, port: port}]
      socket -> [{TelemetryMetricsStatsd, metrics: metrics, socket_path: socket}]
    end
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {WebGamesWeb, :count_users, []}
      # {GamePlatform.Telemetry, :count_active_games, []}
    ]
  end
end
