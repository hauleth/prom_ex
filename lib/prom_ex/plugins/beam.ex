defmodule PromEx.Plugins.Beam do
  @moduledoc """
  Telemetry metrics for the BEAM.

  This plugin captures metrics regarding the Erlang Virtual Machine (i.e the BEAM). Specifically, it captures metrics
  regarding the CPU topology, system limits, VM feature support, scheduler information, memory utilization, distribution
  traffic, and other internal metrics.

  This plugin supports the following options:
  - `poll_rate`: This is option is OPTIONAL and is the rate at which poll metrics are refreshed (default is 5 seconds).

  This plugin exposes the following metric groups:
  - `:beam_memory_polling_metrics`
  - `:beam_cpu_topology_manual_metrics`
  - `:beam_system_limits_manual_metrics`
  - `:beam_system_info_manual_metrics`
  - `:beam_scheduler_manual_metrics`

  To use plugin in your application, add the following to your application supervision tree:
  ```
  def start(_type, _args) do
    children = [
      ...
      {
        PromEx,
        plugins: [
          PromEx.Plugins.Beam
          ...
        ],
        delay_manual_start: :no_delay
      }
    ]

    opts = [strategy: :one_for_one, name: WebApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
  ```

  This plugin exposes manual metrics so be sure to configure the PromEx `:delay_manual_start` as necessary.
  """

  use PromEx.Plugin

  require Logger

  @memory_event [:prom_ex, :plugin, :beam, :memory]

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    # TODO: Investigate Microstate accounting metrics
    # http://erlang.org/doc/man/erlang.html#statistics_microstate_accounting

    [
      memory_metrics(poll_rate),
      mnesia_metrics(poll_rate),
      distribution_metrics(poll_rate),
      beam_internal_metrics(poll_rate)
    ]
  end

  @impl true
  def manual_metrics(_opts) do
    [
      beam_cpu_topology_info(),
      beam_system_limits_info(),
      beam_system_info(),
      beam_scheduler_info()
    ]
  end

  defp distribution_metrics(poll_rate) do
    Polling.build(
      :beam_distribution_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_distribution_metrics, []},
      []
    )
  end

  defp mnesia_metrics(poll_rate) do
    Polling.build(
      :beam_mnesia_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_mnesia_metrics, []},
      []
    )
  end

  defp beam_internal_metrics(poll_rate) do
    Polling.build(
      :beam_internal_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_internal_metrics, []},
      [
        last_value(
          [:beam, :stats, :active_task, :count],
          event_name: [:prom_ex, :plugin, :beam, :active_task, :count],
          description: "The number of processes and ports that are ready to run, or are currently running.",
          measurement: :count,
          tags: [:type]
        ),
        last_value(
          [:beam, :stats, :run_queue, :count],
          event_name: [:prom_ex, :plugin, :beam, :run_queue, :count],
          description: "The number of processes and ports that are ready to run and are in the run queue.",
          measurement: :count,
          tags: [:type]
        ),
        last_value(
          [:beam, :stats, :context_switch, :count],
          event_name: [:prom_ex, :plugin, :beam, :context_switch, :count],
          description: "The total number of context switches since the system started.",
          measurement: :count
        ),
        last_value(
          [:beam, :stats, :reduction, :count],
          event_name: [:prom_ex, :plugin, :beam, :reduction, :count],
          description: "The total number of reductions since the system started.",
          measurement: :count
        ),
        last_value(
          [:beam, :stats, :gc, :count],
          event_name: [:prom_ex, :plugin, :beam, :gc, :count],
          description: "The total number of garbage collections since the system started.",
          measurement: :count
        ),
        last_value(
          [:beam, :stats, :words_reclaimed, :count],
          event_name: [:prom_ex, :plugin, :beam, :words_reclaimed, :count],
          description: "The total number of words reclaimed since the system started.",
          measurement: :count
        ),
        last_value(
          [:beam, :stats, :port_io, :byte, :count],
          event_name: [:prom_ex, :plugin, :beam, :port_io, :count],
          description: "The total number of bytes sent and received through ports since the system started.",
          measurement: :count,
          tags: [:type],
          unit: :byte
        ),
        last_value(
          [:beam, :stats, :uptime, :milliseconds, :count],
          event_name: [:prom_ex, :plugin, :beam, :uptime, :count],
          description: "The total number of wall clock milliseconds that have passed since the system started.",
          measurement: :count,
          unit: :millisecond
        ),
        last_value(
          [:beam, :stats, :port, :count],
          event_name: [:prom_ex, :plugin, :beam, :port, :count],
          description: "A count of how many ports are currently active.",
          measurement: :count
        ),
        last_value(
          [:beam, :stats, :process, :count],
          event_name: [:prom_ex, :plugin, :beam, :process, :count],
          description: "A count of how many Erlang processes are currently running.",
          measurement: :count
        ),
        last_value(
          [:beam, :stats, :atom, :count],
          event_name: [:prom_ex, :plugin, :beam, :atom, :count],
          description: "A count of how many atoms are currently allocated.",
          measurement: :count
        ),
        last_value(
          [:beam, :stats, :ets, :count],
          event_name: [:prom_ex, :plugin, :beam, :ets, :count],
          description: "A count of how many ETS tables currently exist.",
          measurement: :count
        )
      ]
    )
  end

  defp beam_system_info do
    Manual.build(
      :beam_system_info_manual_metrics,
      {__MODULE__, :execute_system_info, []},
      [
        last_value(
          [:beam, :system, :version, :info],
          event_name: [:prom_ex, :plugin, :beam, :version],
          description: "The OTP release major version.",
          measurement: :version
        ),
        last_value(
          [:beam, :system, :smp_support, :info],
          event_name: [:prom_ex, :plugin, :beam, :smp_support],
          description: "Whether the BEAM instance has been compiled with SMP support.",
          measurement: :enabled
        ),
        last_value(
          [:beam, :system, :thread_support, :info],
          event_name: [:prom_ex, :plugin, :beam, :thread_support],
          description: "Whether the BEAM instance has been compiled with threading support.",
          measurement: :enabled
        ),
        last_value(
          [:beam, :system, :time_correction_support, :info],
          event_name: [:prom_ex, :plugin, :beam, :time_correction_support],
          description: "Whether the BEAM instance has time correction support.",
          measurement: :enabled
        ),
        last_value(
          [:beam, :system, :word_size_bytes, :info],
          event_name: [:prom_ex, :plugin, :beam, :word_size_bytes],
          description: "The size of Erlang term words in bytes.",
          measurement: :size
        )
      ]
    )
  end

  defp beam_scheduler_info do
    Manual.build(
      :beam_scheduler_manual_metrics,
      {__MODULE__, :execute_scheduler_info, []},
      [
        last_value(
          [:beam, :system, :dirty_cpu_schedulers, :info],
          event_name: [:prom_ex, :plugin, :beam, :dirty_cpu_schedulers],
          description: "The total number of dirty CPU scheduler threads used by the BEAM.",
          measurement: :quantity
        ),
        last_value(
          [:beam, :system, :dirty_cpu_schedulers_online, :info],
          event_name: [:prom_ex, :plugin, :beam, :dirty_cpu_schedulers_online],
          description: "The total number of dirty CPU schedulers that are online.",
          measurement: :quantity
        ),
        last_value(
          [:beam, :system, :dirty_io_schedulers, :info],
          event_name: [:prom_ex, :plugin, :beam, :dirty_io_schedulers],
          description: "The total number of dirty I/O schedulers used to execute I/O bound native functions.",
          measurement: :quantity
        ),
        last_value(
          [:beam, :system, :schedulers, :info],
          event_name: [:prom_ex, :plugin, :beam, :schedulers],
          description: "The number of scheduler threads in use by the BEAM.",
          measurement: :quantity
        ),
        last_value(
          [:beam, :system, :schedulers_online, :info],
          event_name: [:prom_ex, :plugin, :beam, :schedulers_online],
          description: "The number of scheduler threads that are online.",
          measurement: :quantity
        )
      ]
    )
  end

  defp beam_cpu_topology_info do
    Manual.build(
      :beam_cpu_topology_manual_metrics,
      {__MODULE__, :execute_cpu_topology_info, []},
      [
        last_value(
          [:beam, :system, :logical_processors, :info],
          event_name: [:prom_ex, :plugin, :beam, :logical_processors],
          description: "The total number of logical processors on the host machine.",
          measurement: :quantity
        ),
        last_value(
          [:beam, :system, :logical_processors_available, :info],
          event_name: [:prom_ex, :plugin, :beam, :logical_processors_available],
          description: "The total number of logical processors available to the BEAM.",
          measurement: :quantity
        ),
        last_value(
          [:beam, :system, :logical_processors_online, :info],
          event_name: [:prom_ex, :plugin, :beam, :logical_processors_online],
          description: "The total number of logical processors online on the host machine.",
          measurement: :quantity
        )
      ]
    )
  end

  defp beam_system_limits_info do
    Manual.build(
      :beam_system_limits_manual_metrics,
      {__MODULE__, :execute_system_limits_info, []},
      [
        last_value(
          [:beam, :system, :ets_limit, :info],
          event_name: [:prom_ex, :plugin, :beam, :ets_limit],
          description:
            "The maximum number of ETS tables allowed (this is partially obsolete given that the number of ETS tables is limited by available memory).",
          measurement: :limit
        ),
        last_value(
          [:beam, :system, :port_limit, :info],
          event_name: [:prom_ex, :plugin, :beam, :port_limit],
          description: "The maximum number of ports that can simultaneously exist on the BEAM instance.",
          measurement: :limit
        ),
        last_value(
          [:beam, :system, :process_limit, :info],
          event_name: [:prom_ex, :plugin, :beam, :process_limit],
          description: "The maximum number of processes that can simultaneously exist on the BEAM instance.",
          measurement: :limit
        ),
        last_value(
          [:beam, :system, :thread_pool_size, :info],
          event_name: [:prom_ex, :plugin, :beam, :thread_pool_size],
          description: "The number of async threads in the async threads pool used for async driver calls.",
          measurement: :size
        ),
        last_value(
          [:beam, :system, :atom_limit, :info],
          event_name: [:prom_ex, :plugin, :beam, :atom_limit],
          description: "The maximum number of atoms allowed.",
          measurement: :limit
        )
      ]
    )
  end

  defp memory_metrics(poll_rate) do
    Polling.build(
      :beam_memory_polling_metrics,
      poll_rate,
      {__MODULE__, :execute_memory_metrics, []},
      [
        # Capture the total memory allocated to the entire Erlang VM (or BEAM for short)
        last_value(
          [:beam, :memory, :allocated, :bytes],
          event_name: @memory_event,
          description: "The total amount of memory currently allocated.",
          measurement: :total,
          unit: :byte
        ),

        # Capture the total memory allocated to atoms
        last_value(
          [:beam, :memory, :atom, :total, :bytes],
          event_name: @memory_event,
          description: "The total amount of memory currently allocated for atoms.",
          measurement: :atom,
          unit: :byte
        ),

        # Capture the total memory allocated to binaries
        last_value(
          [:beam, :memory, :binary, :total, :bytes],
          event_name: @memory_event,
          description: "The total amount of memory currently allocated for binaries.",
          measurement: :binary,
          unit: :byte
        ),

        # Capture the total memory allocated to Erlang code
        last_value(
          [:beam, :memory, :code, :total, :bytes],
          event_name: @memory_event,
          description: "The total amount of memory currently allocated for Erlang code.",
          measurement: :code,
          unit: :byte
        ),

        # Capture the total memory allocated to ETS tables
        last_value(
          [:beam, :memory, :ets, :total, :bytes],
          event_name: @memory_event,
          description: "The total amount of memory currently allocated for ETS tables.",
          measurement: :ets,
          unit: :byte
        ),

        # Capture the total memory allocated to Erlang processes
        last_value(
          [:beam, :memory, :processes, :total, :bytes],
          event_name: @memory_event,
          description: "The total amount of memory currently allocated to Erlang processes.",
          measurement: :processes,
          unit: :byte
        )
      ]
    )
  end

  @doc false
  def execute_memory_metrics do
    memory_measurements =
      :erlang.memory()
      |> Map.new()

    :telemetry.execute(@memory_event, memory_measurements, %{})
  end

  @doc false
  def execute_distribution_metrics do
  end

  @doc false
  def execute_internal_metrics do
    total_active_tasks = :erlang.statistics(:total_active_tasks)
    total_active_tasks_all = :erlang.statistics(:total_active_tasks_all)
    total_run_queue_lengths = :erlang.statistics(:total_run_queue_lengths)
    total_run_queue_lengths_all = :erlang.statistics(:total_run_queue_lengths_all)
    dirty_active_tasks = total_active_tasks_all - total_active_tasks
    dirty_run_queue_lengths = total_run_queue_lengths_all - total_run_queue_lengths

    {context_switches, _} = :erlang.statistics(:context_switches)
    {total_reductions, _} = :erlang.statistics(:reductions)
    {number_of_gcs, words_reclaimed, _} = :erlang.statistics(:garbage_collection)
    {{:input, input_port_bytes}, {:output, output_port_bytes}} = :erlang.statistics(:io)
    {wall_clock_time, _} = :erlang.statistics(:wall_clock)

    :telemetry.execute([:prom_ex, :plugin, :beam, :port, :count], %{count: :erlang.system_info(:port_count)})
    :telemetry.execute([:prom_ex, :plugin, :beam, :process, :count], %{count: :erlang.system_info(:process_count)})
    :telemetry.execute([:prom_ex, :plugin, :beam, :atom, :count], %{count: :erlang.system_info(:atom_count)})
    :telemetry.execute([:prom_ex, :plugin, :beam, :ets, :count], %{count: :erlang.system_info(:ets_count)})
    :telemetry.execute([:prom_ex, :plugin, :beam, :active_task, :count], %{count: total_active_tasks}, %{type: :normal})
    :telemetry.execute([:prom_ex, :plugin, :beam, :active_task, :count], %{count: dirty_active_tasks}, %{type: :dirty})
    :telemetry.execute([:prom_ex, :plugin, :beam, :context_switch, :count], %{count: context_switches})
    :telemetry.execute([:prom_ex, :plugin, :beam, :reduction, :count], %{count: total_reductions})
    :telemetry.execute([:prom_ex, :plugin, :beam, :gc, :count], %{count: number_of_gcs})
    :telemetry.execute([:prom_ex, :plugin, :beam, :words_reclaimed, :count], %{count: words_reclaimed})
    :telemetry.execute([:prom_ex, :plugin, :beam, :port_io, :count], %{count: input_port_bytes}, %{type: :input})
    :telemetry.execute([:prom_ex, :plugin, :beam, :port_io, :count], %{count: output_port_bytes}, %{type: :output})
    :telemetry.execute([:prom_ex, :plugin, :beam, :uptime, :count], %{count: wall_clock_time})

    :telemetry.execute([:prom_ex, :plugin, :beam, :run_queue, :count], %{count: total_run_queue_lengths}, %{
      type: :normal
    })

    :telemetry.execute([:prom_ex, :plugin, :beam, :run_queue, :count], %{count: dirty_run_queue_lengths}, %{
      type: :dirty
    })
  end

  @doc false
  def execute_mnesia_metrics do
    # https://github.com/deadtrickster/prometheus.erl/blob/master/src/collectors/mnesia/prometheus_mnesia_collector.erl
  end

  @doc false
  def execute_system_limits_info do
    :telemetry.execute([:prom_ex, :plugin, :beam, :ets_limit], %{limit: :erlang.system_info(:ets_limit)})
    :telemetry.execute([:prom_ex, :plugin, :beam, :port_limit], %{limit: :erlang.system_info(:port_limit)})
    :telemetry.execute([:prom_ex, :plugin, :beam, :process_limit], %{limit: :erlang.system_info(:process_limit)})

    :telemetry.execute(
      [:prom_ex, :plugin, :beam, :thread_pool_size],
      %{size: :erlang.system_info(:thread_pool_size)},
      %{}
    )

    :telemetry.execute([:prom_ex, :plugin, :beam, :atom_limit], %{limit: :erlang.system_info(:atom_limit)}, %{})
  end

  @doc false
  def execute_system_info do
    smp_enabled = if(:erlang.system_info(:smp_support), do: 1, else: 0)
    thread_support_enabled = if(:erlang.system_info(:threads), do: 1, else: 0)
    time_correction_enabled = if(:erlang.system_info(:time_correction), do: 1, else: 0)
    word_size = :erlang.system_info(:wordsize)
    version = :otp_release |> :erlang.system_info() |> :erlang.list_to_binary() |> String.to_integer()

    :telemetry.execute([:prom_ex, :plugin, :beam, :smp_support], %{enabled: smp_enabled}, %{})
    :telemetry.execute([:prom_ex, :plugin, :beam, :thread_support], %{enabled: thread_support_enabled}, %{})
    :telemetry.execute([:prom_ex, :plugin, :beam, :time_correction_support], %{enabled: time_correction_enabled}, %{})
    :telemetry.execute([:prom_ex, :plugin, :beam, :word_size_bytes], %{size: word_size}, %{})
    :telemetry.execute([:prom_ex, :plugin, :beam, :version], %{version: version}, %{})
  end

  @doc false
  def execute_cpu_topology_info do
    :telemetry.execute(
      [:prom_ex, :plugin, :beam, :logical_processors],
      %{quantity: :erlang.system_info(:logical_processors)},
      %{}
    )

    :telemetry.execute(
      [:prom_ex, :plugin, :beam, :logical_processors_available],
      %{quantity: :erlang.system_info(:logical_processors_available)},
      %{}
    )

    :telemetry.execute(
      [:prom_ex, :plugin, :beam, :logical_processors_online],
      %{quantity: :erlang.system_info(:logical_processors_online)},
      %{}
    )
  end

  @doc false
  def execute_scheduler_info do
    :telemetry.execute(
      [:prom_ex, :plugin, :beam, :dirty_cpu_schedulers],
      %{quantity: :erlang.system_info(:dirty_cpu_schedulers)},
      %{}
    )

    :telemetry.execute(
      [:prom_ex, :plugin, :beam, :dirty_cpu_schedulers_online],
      %{quantity: :erlang.system_info(:dirty_cpu_schedulers_online)},
      %{}
    )

    :telemetry.execute(
      [:prom_ex, :plugin, :beam, :dirty_io_schedulers],
      %{quantity: :erlang.system_info(:dirty_io_schedulers)},
      %{}
    )

    :telemetry.execute(
      [:prom_ex, :plugin, :beam, :schedulers],
      %{quantity: :erlang.system_info(:schedulers)},
      %{}
    )

    :telemetry.execute(
      [:prom_ex, :plugin, :beam, :schedulers_online],
      %{quantity: :erlang.system_info(:schedulers_online)},
      %{}
    )
  end
end
