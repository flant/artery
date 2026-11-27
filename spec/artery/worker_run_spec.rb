# frozen_string_literal: true

describe Artery::Worker, '#run' do
  subject(:worker) { described_class.new }

  let(:backend) { instance_double(Artery::Backends::Fake, start: nil, flush: nil) }
  let(:subscribed) { instance_double(Artery::Subscription, subscriber: 'Item', handle: nil) }
  let(:reloaded) { instance_double(Artery::Subscription, subscriber: 'Item', handle: nil) }
  let(:registry) { { Artery::Routing.uri('test.items.new') => [subscribed] } }
  let(:callbacks) { {} }

  before do
    allow(Artery).to receive_messages(backend: backend, handle_signals: nil)
    allow(Artery).to receive(:worker=)
    allow(Artery).to receive(:subscriptions) { registry }
    allow(Artery::Sync).to receive(:new).and_return(instance_double(Artery::Sync, execute: nil))
    allow(backend).to receive(:start).and_yield
    allow(backend).to receive(:subscribe) { |route, *, &callback| callbacks[route] = callback }
    worker.run
  end

  context 'when code reloading registers the subscriptions of a model again' do
    before do
      registry[Artery::Routing.uri('test.items.new')] = [reloaded]
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands messages to the subscriptions registered again', :aggregate_failures do
      expect(reloaded).to have_received(:handle)
      expect(subscribed).not_to have_received(:handle)
    end
  end

  context 'when code reloading has unloaded a model that is not loaded again yet' do
    before do
      registry.clear
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands messages to the subscriptions the worker subscribed with' do
      expect(subscribed).to have_received(:handle)
    end
  end

  context 'without code reloading' do
    before do
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands each message to every subscription once' do
      expect(subscribed).to have_received(:handle).once
    end
  end
end
