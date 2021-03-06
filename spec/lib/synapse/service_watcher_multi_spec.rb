require 'spec_helper'
require 'synapse/service_watcher/multi/multi'
require 'synapse/service_watcher/zookeeper/zookeeper'
require 'synapse/service_watcher/dns/dns'
require 'synapse/service_watcher/multi/resolver/base'

describe Synapse::ServiceWatcher::MultiWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end

  subject {
    Synapse::ServiceWatcher::MultiWatcher.new(config, mock_synapse, reconfigure_callback)
  }

  let(:reconfigure_callback) { ->(*args) {} }

  let(:discovery) do
    valid_discovery
  end

  let (:zk_discovery) do
    {'method' => 'zookeeper', 'hosts' => ['localhost:2181'], 'path' => '/smartstack'}
  end

  let (:dns_discovery) do
    {'method' => 'dns', 'servers' => ['localhost']}
  end

  let(:valid_discovery) do
    {'method' => 'multi',
     'watchers' => {
       'primary' => zk_discovery,
       'secondary' => dns_discovery,
     },
     'resolver' => {
       'method' => 'base',
     }}
  end

  let(:config) do
    {
      'name' => 'test',
      'haproxy' => {},
      'discovery' => discovery,
    }
  end

  describe '.initialize' do
    subject {
      Synapse::ServiceWatcher::MultiWatcher
    }

    context 'with empty configuration' do
      let(:discovery) do
        {}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with empty watcher configuration' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with undefined watchers' do
      let(:discovery) do
        {'method' => 'muli'}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with wrong method type' do
      let(:discovery) do
        {'method' => 'zookeeper', 'watchers' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with invalid child watcher definition' do
      let(:discovery) {
        {'method' => 'multi', 'watchers' => {
           'secondary' => {
             'method' => 'bogus',
           }
         }}
      }

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with invalid child watcher type' do
      let(:discovery) {
        {'method' => 'multi', 'watchers' => {
           'child' => 'not_a_hash'
         }}
      }

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with undefined resolver' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {
           'child' => zk_discovery
         }}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with empty resolver' do
      let(:discovery) do
        {'method' => 'multi', 'watchers' => {
           'child' => zk_discovery
         },
        'resolver' => {}}
      end

      it 'raises an error' do
        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.to raise_error ArgumentError
      end
    end

    context 'with valid configuration' do
      let(:discovery) do
        valid_discovery
      end

      it 'creates the requested watchers' do
        expect(Synapse::ServiceWatcher::ZookeeperWatcher)
          .to receive(:new)
          .with({'name' => 'test', 'haproxy' => {}, 'discovery' => zk_discovery}, mock_synapse, duck_type(:call))
          .and_call_original
        expect(Synapse::ServiceWatcher::DnsWatcher)
          .to receive(:new)
          .with({'name' => 'test', 'haproxy' => {}, 'discovery' => dns_discovery}, mock_synapse, duck_type(:call))
          .and_call_original

        expect {
          subject.new(config, mock_synapse, reconfigure_callback)
        }.not_to raise_error
      end

      it 'creates the requested resolver' do
        expect(Synapse::ServiceWatcher::Resolver::BaseResolver)
          .to receive(:new)
          .with({'method' => 'base'},
                {'primary' => instance_of(Synapse::ServiceWatcher::ZookeeperWatcher),
                 'secondary' => instance_of(Synapse::ServiceWatcher::DnsWatcher)},
                duck_type(:call))
          .and_call_original

        expect { subject.new(config, mock_synapse, reconfigure_callback) }.not_to raise_error
      end

      it 'sets @watchers to each watcher' do
        multi_watcher = subject.new(config, mock_synapse, reconfigure_callback)
        watchers = multi_watcher.instance_variable_get(:@watchers)

        expect(watchers.has_key?('primary'))
        expect(watchers.has_key?('secondary'))

        expect(watchers['primary']).to be_instance_of(Synapse::ServiceWatcher::ZookeeperWatcher)
        expect(watchers['secondary']).to be_instance_of(Synapse::ServiceWatcher::DnsWatcher)
      end

      it 'sets @resolver to the requested resolver type' do
        watcher = subject.new(config, mock_synapse, reconfigure_callback)
        resolver = watcher.instance_variable_get(:@resolver)

        expect(resolver).to be_instance_of(Synapse::ServiceWatcher::Resolver::BaseResolver)
      end
    end
  end

  describe '.start' do
    it 'starts all child watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:start)
      end

      expect { subject.start }.not_to raise_error
    end

    it 'starts resolver' do
      resolver = subject.instance_variable_get(:@resolver)
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        allow(w).to receive(:start)
      end

      expect(resolver).to receive(:start)
      expect { subject.start }.not_to raise_error
    end
  end

  describe '.stop' do
    it 'stops all child watchers' do
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        expect(w).to receive(:stop)
      end

      expect { subject.stop }.not_to raise_error
    end

    it 'stops resolver' do
      resolver = subject.instance_variable_get(:@resolver)
      watchers = subject.instance_variable_get(:@watchers).values
      watchers.each do |w|
        allow(w).to receive(:stop)
      end

      expect(resolver).to receive(:stop)
      expect { subject.stop }.not_to raise_error
    end
  end

  describe ".backends" do
    it "returns resolver.merged_backends" do
      resolver = subject.instance_variable_get(:@resolver)
      expect(resolver).to receive(:merged_backends).exactly(:once).and_return(["test-a", "test-b"])
      expect(subject.backends).to eq(["test-a", "test-b"])
    end
  end

  describe ".config_for_generator" do
    it 'calls resolver.merged_config_for_generator' do
      resolver = subject.instance_variable_get(:@resolver)
      expect(resolver).to receive(:merged_config_for_generator).exactly(:once).and_return({'haproxy' => 'custom config'})
      expect(subject.config_for_generator).to eq({'haproxy' => 'custom config'})
      end
  end

  describe ".ping?" do
    context 'when resolver returns false' do
      it 'returns false' do
        resolver = subject.instance_variable_get(:@resolver)
        allow(resolver).to receive(:healthy?).and_return(false)

        expect(subject.ping?).to eq(false)
      end
    end

    context 'when resolver returns true' do
      it 'returns true' do
        resolver = subject.instance_variable_get(:@resolver)
        allow(resolver).to receive(:healthy?).and_return(true)

        expect(subject.ping?).to eq(true)
      end
    end
  end

  describe "resolver" do
    context 'when resolver sends a notification' do
      let(:mock_backends) { ['host_1', 'host_2'] }
      let(:mock_config) { {'haproxy' => 'mock config'} }

      it 'sets backends to resolver backends' do
        expect(subject).to receive(:resolver_notification).exactly(:once).and_call_original
        expect(subject).to receive(:set_backends).exactly(:once).with(mock_backends, mock_config)

        resolver = subject.instance_variable_get(:@resolver)
        allow(resolver).to receive(:merged_backends).exactly(:once).and_return(mock_backends)
        allow(resolver).to receive(:merged_config_for_generator).exactly(:once).and_return(mock_config)

        resolver.send(:send_notification)
      end
    end
  end

  describe 'child watchers' do
    context 'when they have an update' do
      it 'increments @revision' do
        w = subject.instance_variable_get(:@watchers).values[0]

        expect { w.send(:reconfigure!) }.to change { subject.instance_variable_get(:@revision) }.by_at_least(1)
      end

      it 'calls reconfigure! on multi watcher' do
        expect(subject).to receive(:reconfigure!).at_least(:once)

        w = subject.instance_variable_get(:@watchers).values[0]
        w.send(:reconfigure!)
      end
    end
  end
end
