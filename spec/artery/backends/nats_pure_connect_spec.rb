# frozen_string_literal: true

describe Artery::Backends::NATSPure, '#connect' do
  subject(:backend) { described_class.new({}) }

  let(:server_uri) { URI.parse('nats://tfprod:secret@nats.infra:4222') }
  let(:handlers) { {} }
  let(:payloads) { [] }
  let(:nats_client) do
    instance_double(NATS::Client, connected_server: server_uri, connected?: true).tap do |client|
      allow(client).to receive(:on_error)
      allow(client).to receive(:on_reconnect) { |&block| handlers[:reconnect] = block }
      allow(client).to receive(:on_disconnect)
      allow(client).to receive(:on_close)
    end
  end

  around do |example|
    env = ENV.to_h
    ENV.delete('ARTERY_INBOX_PREFIX')
    example.run
  ensure
    ENV.replace(env)
  end

  before do
    allow(NATS).to receive(:connect).and_return(nats_client)
    allow(Artery::Instrumentation).to receive(:instrument) { |_name, payload| payloads << payload }
  end

  it 'does not pass credentials on connected' do
    backend.connect

    expect(payloads.first[:state]).to eq(:connected)
    expect(payloads.first[:server].to_s).to eq('nats://nats.infra:4222')
  end

  it 'does not pass credentials on reconnected' do
    backend.connect
    handlers[:reconnect].call

    expect(payloads.last[:state]).to eq(:reconnected)
    expect(payloads.last[:server].to_s).to eq('nats://nats.infra:4222')
  end

  it 'does not pass auth token given as user without password' do
    allow(nats_client).to receive(:connected_server).and_return(URI.parse('nats://s3cr3t-token@nats.infra:4222'))

    backend.connect

    expect(payloads.first[:server].to_s).to eq('nats://nats.infra:4222')
  end

  it 'does not modify the client server uri' do
    backend.connect

    expect(server_uri.to_s).to eq('nats://tfprod:secret@nats.infra:4222')
  end

  it 'passes nil when client is not connected' do
    allow(nats_client).to receive(:connected_server).and_return(nil)

    backend.connect

    expect(payloads.first[:server]).to be_nil
  end

  it 'handles string server' do
    allow(nats_client).to receive(:connected_server).and_return('nats://tfprod:secret@nats.infra:4222')

    backend.connect

    expect(payloads.first[:server].to_s).to eq('nats://nats.infra:4222')
  end

  context 'when connected' do
    before do
      backend.connect
    end

    it 'receives replies under the inbox prefix of the service' do
      expect(NATS).to have_received(:connect).with(hash_including(custom_inbox_prefix: '_INBOX.test'))
    end
  end

  context 'when connected with configured inbox prefix' do
    subject(:backend) { described_class.new(inbox_prefix: '_INBOX.custom') }

    before do
      backend.connect
    end

    it 'receives replies under the configured prefix' do
      expect(NATS).to have_received(:connect).with(hash_including(custom_inbox_prefix: '_INBOX.custom'))
    end
  end

  context 'when connected with inbox prefix in the environment' do
    before do
      ENV['ARTERY_INBOX_PREFIX'] = '_INBOX.env'
      backend.connect
    end

    it 'receives replies under the prefix from the environment' do
      expect(NATS).to have_received(:connect).with(hash_including(custom_inbox_prefix: '_INBOX.env'))
    end
  end

  context 'when connected with inbox prefix both configured and in the environment' do
    subject(:backend) { described_class.new(inbox_prefix: '_INBOX.custom') }

    before do
      ENV['ARTERY_INBOX_PREFIX'] = '_INBOX.env'
      backend.connect
    end

    it 'receives replies under the configured prefix' do
      expect(NATS).to have_received(:connect).with(hash_including(custom_inbox_prefix: '_INBOX.custom'))
    end
  end

  context 'when connected without service name' do
    before do
      allow(Artery).to receive(:service_name?).and_return(false)
      backend.connect
    end

    it 'keeps the default inbox prefix of nats-pure' do
      expect(NATS).to have_received(:connect).with(hash_excluding(:custom_inbox_prefix))
    end
  end
end
