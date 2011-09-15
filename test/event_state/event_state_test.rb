require 'event_state'
require 'test/unit'

# load example machines
require 'event_state/ex_echo'
require 'event_state/ex_secret'

class TestEventState < Test::Unit::TestCase
  include EventState

  DEFAULT_HOST = 'localhost'
  DEFAULT_PORT = 14159

  def run_server_and_client server_class, client_class, opts={}, &block
    host = opts[:host] || DEFAULT_HOST
    port = opts[:port] || DEFAULT_PORT
    server_args = opts[:server_args] || []
    client_args = opts[:client_args] || []

    client = nil
    EM.run do
      EventMachine.start_server host, port, server_class, *server_args
      client = EventMachine.connect(host, port, client_class,
                                    *client_args, &block)
    end
    client
  end

  def run_echo_test client_class
    server_log = []
    recorder = run_server_and_client(LoggingEchoServer, client_class,
      server_args: [server_log],
      client_args: [%w(foo bar baz), []]).recorder

    assert_equal [
      "entering listening state", # on_enter called on the start state
      "exiting listening state",  # when a message is received
      "echoing foo",              # the first noise
      "exiting echoing state",    # sent echo to client
      "entering listening state", # now listening for next noise
      "exiting listening state",  # ...
      "echoing bar",
      "exiting echoing state",
      "entering listening state",
      "exiting listening state",
      "echoing baz",
      "exiting echoing state",
      "entering listening state"], server_log
  end
  
  def test_echo_basic
    assert_equal %w(foo bar baz), 
      run_server_and_client(EchoServer, EchoClient,
        client_args: [%w(foo bar baz), []]).recorder
  end

  def test_delayed_echo
    assert_equal %w(foo bar baz), 
      run_server_and_client(DelayedEchoServer, EchoClient,
        server_args: [0.5],
        client_args: [%w(foo bar baz), []]).recorder
  end

  def test_echo_with_object_protocol_client
    run_echo_test ObjectProtocolEchoClient
  end

  def test_echo_with_event_state_client
    run_echo_test EchoClient
  end

  def test_secret_server
    run_server_and_client(TopSecretServer, TopSecretClient)
  end
  
  def test_print_state_machine_dot
    assert_equal <<DOT, EchoClient.print_state_machine_dot(nil, 'rankdir=LR;')
digraph "EventState::EchoClient" {
  rankdir=LR;
  speaking [peripheries=2];
  speaking -> listening [color=red,label="echo_message"];
  listening -> speaking [color=blue,label="echo_message"];
}
DOT
  end

  def test_class_name_to_message_name
    assert_equal :my_message,
      EventState::Message.class_name_to_message_name('MyMessage')
    assert_equal :my_message,
      EventState::Message.class_name_to_message_name('Foo::MyMessage')
    assert_equal :my_message,
      EventState::Message.class_name_to_message_name('Foo::Bar::MyMessage')
    assert_equal :my_t_l_a, # not necessarily good... but simple
      EventState::Message.class_name_to_message_name('Foo::Bar::MyTLA')
  end

  #
  # 
  #
  class MachineDSLTester
    include EventState::MachineDSL
  end

  def test_dsl_basic
    #
    # check that we get the transitions right for this simple DSL
    #
    t = MachineDSLTester.new
    t.state :foo do
      t.on_recv :hello, :bar
    end
    t.state :bar do 
      t.on_recv :good_bye, :foo
    end

    assert_equal [
      [:foo, :recv, :hello, :bar],
      [:bar, :recv, :good_bye, :foo]], t.transitions
  end

  def test_dsl_no_nested_states
    #
    # nested state blocks are illegal
    #
    t = MachineDSLTester.new
    assert_raises(RuntimeError) {
      t.state :foo do
        t.state :bar do
        end
      end
    }
  end
end

