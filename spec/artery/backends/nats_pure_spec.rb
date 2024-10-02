# frozen_string_literal: true

describe Artery::Backends::NATSPure do
  before do
    Artery.use_backend :nats_pure
  end

  it 'initializes backend' do
    expect(Artery.backend).to be_a described_class
  end

  it 'connects' do
    expect do
      Artery.connect
    end.not_to raise_error

    expect(Artery.backend.client).to be_a NATS::Client
  end

  it 'receives a message when subscribed' do
    received = []
    Artery.subscribe('hello.world') { |m| received << m }

    5.times do |x|
      Artery.publish('hello.world', { idx: x })
    end

    sleep 0.1

    expect(received.count).to eq(5)
    expect(received.map { |m| m['idx'] }.sort).to eq((0..4).to_a)
  end

  it 'handles error on incorrect message format' do
    allow(Artery.error_handler).to receive(:handle)

    received = []
    Artery.subscribe('hello.world') { |m| received << m }

    Artery.publish('hello.world', 'string-not-json')

    sleep 0.1

    expect(Artery.error_handler).to have_received(:handle).with(Artery::FormatError)
  end

  it 'handles a response for request' do
    Artery.subscribe('hello.world.square') do |m, reply_to|
      Artery.publish reply_to, { square: m['num']**2 }
    end

    result = nil
    Artery.request('hello.world.square', { num: 5 }, timeout: 0.5) do |on|
      on.success do |resp|
        result = resp['square']
      end
    end

    expect(result).to eq(5**2)
  end
end
