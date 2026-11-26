# frozen_string_literal: true

describe Artery::Worker do
  let(:worker) { described_class.new }
  let(:backend) { instance_double(Artery::Backends::Fake) }
  let(:inbox) { '_INBOX.123' }
  let(:failure) { ->(_message) { raise 'handler failed' } }
  let(:success) { ->(message) { Artery.publish(message.reply, id: 42) } }

  before do
    allow(Artery).to receive_messages(backend: backend, handle_signals: nil)
    allow(Artery).to receive(:worker=)
    allow(Artery).to receive(:handle_error)
    allow(worker).to receive(:subscribe_healthz)
    allow(Artery::Sync).to receive(:new).and_return(instance_double(Artery::Sync, execute: nil))
    allow(backend).to receive(:start).and_yield
    allow(backend).to receive(:publish)
    allow(backend).to receive(:flush)
  end

  def deliver(*handlers, reply: inbox)
    route = 'test.items.new'
    subscriptions = handlers.map do |handler|
      instance_double(Artery::Subscription, subscriber: 'Item').tap do |subscription|
        allow(subscription).to receive(:handle, &handler)
      end
    end
    allow(Artery).to receive(:subscriptions).and_return({ Artery::Routing.uri(route) => subscriptions })
    allow(backend).to receive(:subscribe).with(route, anything).and_yield('{}', reply, route)
    worker.run
  end

  it 'reports each exception and returns one generic error when all subscriptions fail' do
    deliver(failure, failure)

    expect(Artery).to have_received(:handle_error).with(described_class::Error).twice
    expect(backend).to have_received(:publish).with(inbox, '{"error":"internal_error"}').once
  end

  it 'lets a later subscription reply after an earlier failure' do
    deliver(failure, success)

    expect(backend).to have_received(:publish).with(inbox, '{"id":42}').once
    expect(backend).to have_received(:publish).once
  end

  it 'preserves an application error even if the same handler subsequently fails' do
    deliver(lambda do |message|
      Artery.publish(message.reply, error: 'not_found')
      raise 'after reply'
    end)

    expect(backend).to have_received(:publish).with(inbox, '{"error":"not_found"}').once
    expect(backend).to have_received(:publish).once
  end

  it 'ignores publications to unrelated subjects when deciding whether to reply' do
    deliver(->(_message) { Artery.publish('test.items.changed', id: 42) }, failure)

    expect(backend).to have_received(:publish).with(inbox, '{"error":"internal_error"}')
  end

  it 'preserves multiple explicit replies' do
    deliver(success, success, failure)

    expect(backend).to have_received(:publish).with(inbox, '{"id":42}').twice
    expect(backend).to have_received(:publish).twice
  end

  it 'keeps overlapping deliveries independent' do
    pause = ->(_message) { Fiber.yield }
    first = Fiber.new { deliver(pause, success, failure) }
    second = Fiber.new { deliver(pause, failure, reply: '_INBOX.other') }

    first.resume
    second.resume
    first.resume
    second.resume

    expect(backend).to have_received(:publish).with(inbox, '{"id":42}').once
    expect(backend).to have_received(:publish).with('_INBOX.other', '{"error":"internal_error"}').once
    expect(backend).to have_received(:publish).twice
  end

  it 'can send the fallback if publishing an application reply raised' do
    allow(backend).to receive(:publish).with(inbox, '{"id":42}').and_raise(IOError, 'disconnected')
    deliver(success)

    expect(backend).to have_received(:publish).with(inbox, '{"error":"internal_error"}').once
    expect(Artery).to have_received(:handle_error).with(described_class::Error).once
  end

  it 'leaves an intentionally unanswered request alone' do
    deliver(->(_message) {})

    expect(backend).not_to have_received(:publish)
  end

  it 'only reports the exception for a delivery without a reply inbox' do
    deliver(failure, reply: nil)

    expect(Artery).to have_received(:handle_error).with(described_class::Error)
    expect(backend).not_to have_received(:publish)
  end

  context 'when subscribed' do
    before do
      deliver(success)
    end

    it 'waits for the server to confirm subscriptions', :aggregate_failures do
      expect(backend).to have_received(:subscribe).ordered
      expect(backend).to have_received(:flush).ordered
    end
  end

  context 'when the server does not confirm subscriptions' do
    before do
      allow(backend).to receive(:flush).and_raise(NATS::IO::Timeout)
      deliver(success)
    end

    it 'reports the failure without subscribing again', :aggregate_failures do
      expect(backend).to have_received(:subscribe).once
      expect(Artery).to have_received(:handle_error).with(described_class::Error)
    end
  end

  it 'reports failure to publish the fallback without re-running subscriptions' do
    allow(backend).to receive(:publish).and_raise(IOError, 'disconnected')
    deliver(failure)

    expect(backend).to have_received(:publish).once
    expect(Artery).to have_received(:handle_error).with(described_class::Error).twice
  end
end
