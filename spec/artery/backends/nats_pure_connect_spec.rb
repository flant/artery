# frozen_string_literal: true

describe Artery::Backends::NATSPure, '#connect' do
  subject(:backend) { described_class.new({}) }

  let(:server_uri) { URI.parse('nats://tfprod:secret@nats.infra:4222') }
  let(:handlers) { {} }
  let(:payloads) { [] }
  let(:nats_client) do
    instance_double(NATS::Client, connected_server: server_uri, connected?: true).tap do |client|
      allow(client).to receive(:on_reconnect) { |&block| handlers[:reconnect] = block }
      allow(client).to receive(:on_disconnect)
      allow(client).to receive(:on_close)
    end
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
end
