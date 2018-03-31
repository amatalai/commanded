defmodule Commanded.Commands.DispatchConsistencyTest do
  use Commanded.StorageCase

  alias Commanded.Commands.{
    ConsistencyAggregateRoot,
    ConsistencyRouter,
    ConsistencyPrefixRouter,
    EventuallyConsistentEventHandler,
    ExecutionResult,
    OptionalStronglyConsistentEventHandler,
    StronglyConsistentEventHandler,
  }
  alias Commanded.EventStore
  alias Commanded.Helpers.ProcessHelper
  alias ConsistencyAggregateRoot.{
    ConsistencyCommand,
    NoOpCommand,
    RequestDispatchCommand,
  }

  setup do
    {:ok, handler1} = StronglyConsistentEventHandler.start_link()
    {:ok, handler2} = EventuallyConsistentEventHandler.start_link()

    on_exit fn ->
      ProcessHelper.shutdown(handler1)
      ProcessHelper.shutdown(handler2)
    end

    :ok
  end

  test "should wait for strongly consistent event handler to handle event" do
    command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 0}
    assert :ok = ConsistencyRouter.dispatch(command, consistency: :strong)
  end

  # default consistency timeout set to 100ms test config
  test "should timeout waiting for strongly consistent event handler to handle event" do
    command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 5_000}
    assert {:error, :consistency_timeout} = ConsistencyRouter.dispatch(command, consistency: :strong)
  end

  test "should not wait when command creates no events" do
    command = %NoOpCommand{uuid: UUID.uuid4()}
    assert :ok = ConsistencyRouter.dispatch(command, consistency: :strong)
  end

  test "should allow strongly consistent event handler to dispatch a command" do
    command = %RequestDispatchCommand{uuid: UUID.uuid4(), delay: 0}
    assert :ok = ConsistencyRouter.dispatch(command, consistency: :strong)
  end

  test "should timeout waiting for strongly consistent handler dispatching a command" do
    command = %RequestDispatchCommand{uuid: UUID.uuid4(), delay: 5_000}
    assert {:error, :consistency_timeout} = ConsistencyRouter.dispatch(command, consistency: :strong)
  end

  describe "optional `:strong` consistency" do
    setup do
      {:ok, handler3} = OptionalStronglyConsistentEventHandler.start_link()

      on_exit fn ->
        ProcessHelper.shutdown(handler3)
      end

      :ok
    end

    test "should only wait for opt-in strongly consistent event handler to handle event" do
      command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 100}
      opts = [consistency: [OptionalStronglyConsistentEventHandler]]

      assert :ok = ConsistencyRouter.dispatch(command, opts)
    end

    # default consistency timeout set to 100ms test config
    test "should timeout waiting for strongly consistent event handler to handle event" do
      command = %ConsistencyCommand{uuid: UUID.uuid4(), delay: 5_000}
      opts = [consistency: ["OptionalStronglyConsistentEventHandler"]]

      assert {:error, :consistency_timeout} = ConsistencyRouter.dispatch(command, opts)
    end
  end

  describe "aggregate identity prefix" do
    test "should wait for strongly consistent event handler to handle event" do
      uuid = UUID.uuid4()
      command = %ConsistencyCommand{uuid: uuid, delay: 0}

      assert :ok = ConsistencyPrefixRouter.dispatch(command, consistency: :strong)
    end

    test "should append events to stream using prefixed aggregate uuid" do
      uuid = UUID.uuid4()
      command = %ConsistencyCommand{uuid: uuid, delay: 0}

      assert {:ok, %ExecutionResult{aggregate_uuid: aggregate_uuid}}
        = ConsistencyPrefixRouter.dispatch(command, consistency: :strong, include_execution_result: true)

      assert aggregate_uuid == "example-prefix-" <> uuid

      recorded_events = EventStore.stream_forward(aggregate_uuid) |> Enum.to_list()
      assert length(recorded_events) == 1
    end
  end
end
