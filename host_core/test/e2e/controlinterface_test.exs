defmodule HostCore.E2E.ControlInterfaceTest do
  use ExUnit.Case, async: false

  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  setup do
    {:ok, evt_watcher} =
      GenServer.start_link(HostCoreTest.EventWatcher, HostCore.Host.lattice_prefix())

    on_exit(fn ->
      HostCore.Linkdefs.Manager.del_link_definition(@kvcounter_key, @redis_contract, @redis_link)
    end)

    [
      evt_watcher: evt_watcher
    ]
  end

  @echo_key HostCoreTest.Constants.echo_key()
  @echo_path HostCoreTest.Constants.echo_path()
  @kvcounter_key HostCoreTest.Constants.kvcounter_key()
  @redis_key HostCoreTest.Constants.redis_key()
  @redis_link HostCoreTest.Constants.default_link()
  @redis_contract HostCoreTest.Constants.keyvalue_contract()

  test "can get claims", %{:evt_watcher => _evt_watcher} do
    on_exit(fn -> HostCore.Host.purge() end)
    {:ok, bytes} = File.read(@echo_path)
    {:ok, _pid} = HostCore.Actors.ActorSupervisor.start_actor(bytes)

    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.ctl.#{prefix}.get.claims"

    Tracer.with_span "Make claims request", kind: :client do
      Logger.debug("Making claims request")

      {:ok, %{body: body}} =
        HostCore.Nats.safe_req(:control_nats, topic, [], receive_timeout: 2_000)

      echo_claims =
        body
        |> Jason.decode!()
        |> Map.get("claims")
        |> Enum.find(fn claims -> Map.get(claims, "sub") == @echo_key end)

      assert Map.get(echo_claims, "sub") == @echo_key
    end
  end

  test "can get linkdefs", %{:evt_watcher => _evt_watcher} do
    :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        @redis_contract,
        @redis_link,
        @redis_key,
        %{URL: "redis://127.0.0.1:6379"}
      )

    prefix = HostCore.Host.lattice_prefix()
    topic = "wasmbus.ctl.#{prefix}.get.links"

    {:ok, %{body: body}} =
      HostCore.Nats.safe_req(:control_nats, topic, [], receive_timeout: 2_000)

    kvcounter_redis_link =
      body
      |> Jason.decode!()
      |> Map.get("links")
      |> Enum.find(fn linkdef ->
        Map.get(linkdef, "actor_id") == @kvcounter_key &&
          Map.get(linkdef, "provider_id") == @redis_key
      end)

    assert Map.get(kvcounter_redis_link, "actor_id") == @kvcounter_key
    assert Map.get(kvcounter_redis_link, "provider_id") == @redis_key
    assert Map.get(kvcounter_redis_link, "contract_id") == @redis_contract
    assert Map.get(kvcounter_redis_link, "link_name") == @redis_link
  end

  test "cannot cache multiple linkdefs" do
    assert :ok =
      HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        @redis_contract,
        @redis_link,
        @redis_key,
        %{URL: "redis://127.0.0.1:6379"}
      )

    assert {:error, {:duplicate_key, {@kvcounter_key, @redis_contract, @redis_link}}} = HostCore.Linkdefs.Manager.put_link_definition(
        @kvcounter_key,
        @redis_contract,
        @redis_link,
        @redis_key,
        %{URL: "redis://127.0.0.1:6379"}
      )
  end
end
