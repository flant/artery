# frozen_string_literal: true

describe Artery::Backends::NATSPure, '#request' do
  let(:backend) { described_class.new({}) }
  let(:nats_client) { instance_double(NATS::Client, connected_server: nil, connected?: true) }
  let(:errors) { [] }

  before do
    allow(nats_client).to receive_messages(on_reconnect: nil, on_disconnect: nil, on_close: nil)
    allow(NATS).to receive(:connect).and_return(nats_client)
    allow(Artery).to receive(:backend).and_return(backend)
  end

  def request
    Artery.request('test.sources.get_all', { page: 0 }) do |on|
      on.success { |_data| raise 'unexpected success' }
      on.error { |error| errors << error }
    end
  end

  context 'when nobody listens on the route' do
    before { allow(nats_client).to receive(:request).and_raise(NATS::IO::NoRespondersError) }

    it 'passes the failure to the error handler of the request' do
      request

      expect(errors).to contain_exactly(an_instance_of(Artery::NoRespondersError))
      expect(errors.first.message).to eq('No responders for test.sources.get_all')
      expect(errors.first.artery_context).to eq(request: { route: 'test.sources.get_all', data: '{"page":0}' })
    end
  end

  context 'when the request times out' do
    before { allow(nats_client).to receive(:request).and_raise(NATS::IO::Timeout) }

    it 'passes the failure to the error handler of the request' do
      request

      expect(errors).to contain_exactly(an_instance_of(Artery::TimeoutError))
    end
  end
end
