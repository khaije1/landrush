$:.push(File.expand_path('../../lib', __FILE__))

require 'bundler/setup'
require 'minitest/spec'

require 'landrush'
require 'landrush/cap/linux/configured_dns_servers'
require 'landrush/cap/linux/read_host_visible_ip_address'
require 'landrush/cap/linux/redirect_dns'

require 'minitest/autorun'
require 'mocha/mini_test'

def fake_environment(options = { enabled: true })
  # For the home_path we want the base Vagrant directory
  vagrant_test_home = Pathname(Landrush::Server.working_dir).parent.parent
  { machine: fake_machine(options), ui: FakeUI, home_path: vagrant_test_home }
end

class RecordingCommunicator
  attr_reader :commands, :responses

  def initialize
    @commands = Hash.new([])
    @responses = Hash.new('')
  end

  def stub_command(command, response)
    responses[command] = response
  end

  def sudo(command)
    puts "SUDO: #{command}"
    commands[:sudo] << command
    responses[command]
  end

  def execute(command)
    commands[:execute] << command
    responses[command].split("\n").each do |line|
      yield(:stdout, "#{line}\n")
    end
  end

  def test(command)
    commands[:test] << command
    true
  end

  def ready?
    true
  end
end

module Landrush
  class FakeProvider
    def initialize(*args)
    end

    def _initialize(*args)
    end

    def ssh_info
    end

    def state
      @state ||= Vagrant::MachineState.new('fake-state', 'fake-state', 'fake-state')
    end
  end
end

module Landrush
  class FakeConfig
    def landrush
      @landrush_config ||= Landrush::Config.new
    end

    def vm
      VagrantPlugins::Kernel_V2::VMConfig.new
    end
  end
end

def fake_machine(options={})
  env = options.fetch(:env, Vagrant::Environment.new)
  machine = Vagrant::Machine.new(
    'fake_machine',
    'fake_provider',
    Landrush::FakeProvider,
    'provider_config',
    {}, # provider_options
    env.vagrantfile.config, # config
    Pathname('data_dir'),
    'box',
    options.fetch(:env, Vagrant::Environment.new),
    env.vagrantfile
  )

  machine.instance_variable_set("@communicator", RecordingCommunicator.new)
  machine.communicate.stub_command(
    Landrush::Cap::Linux::ReadHostVisibleIpAddress.command,
    "#{options.fetch(:ip, '1.2.3.4')}\n"
  )

  machine.config.landrush.enabled = options.fetch(:enabled, false)
  machine.config.vm.hostname = options.fetch(:hostname, 'somehost.vagrant.test')

  machine
end

def fake_static_entry(env, hostname, ip)
  env[:machine].config.landrush.host(hostname, ip)
  Landrush::Store.hosts.set(hostname, ip)
end

module MiniTest
  class Spec
    alias_method :hush, :capture_io
  end
end

# order is important on these
require 'support/create_fake_working_dir'

require 'support/clear_dependent_vms'

require 'support/fake_ui'
require 'support/test_server_daemon'
require 'support/fake_resolver_config'

require 'support/delete_fake_working_dir'
