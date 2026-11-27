# frozen_string_literal: true

describe Artery::Worker, '#run' do
  subject(:worker) { described_class.new }

  let(:backend) { instance_double(Artery::Backends::Fake, start: nil, flush: nil) }
  let(:item) { class_double(Source, name: 'Item') }
  let(:subscribed) do
    instance_double(Artery::Subscription, uri: Artery::Routing.uri('test.items.new'), subscriber: item, handle: nil)
  end
  let(:reloaded) do
    instance_double(Artery::Subscription, uri: Artery::Routing.uri('test.items.new'), subscriber: item, handle: nil)
  end
  let(:callbacks) { {} }

  around do |example|
    unloaded = Artery.instance_variable_get(:@unloaded_subscriptions)
    example.run
  ensure
    Artery.instance_variable_set(:@unloaded_subscriptions, unloaded)
  end

  before do
    allow(Artery).to receive_messages(backend: backend, handle_signals: nil)
    allow(Artery).to receive(:worker=)
    allow(Artery::Sync).to receive(:new).and_return(instance_double(Artery::Sync, execute: nil))
    allow(backend).to receive(:start).and_yield
    allow(backend).to receive(:subscribe) { |route, *, &callback| callbacks[route] = callback }
    Artery.add_subscription(subscribed)
    worker.run
  end

  after do
    Artery.unregister_model(item)
  end

  context 'without code reloading' do
    before do
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands each message to every subscription once' do
      expect(subscribed).to have_received(:handle).once
    end
  end

  context 'when code reloading has unloaded a model that is not loaded again yet' do
    before do
      Artery.unregister_model(item)
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands messages to the subscriptions the model had' do
      expect(subscribed).to have_received(:handle)
    end
  end

  context 'when code reloading loads the model again' do
    before do
      Artery.unregister_model(item)
      Artery.register_model(item)
      Artery.add_subscription(reloaded)
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands messages to its new subscriptions only', :aggregate_failures do
      expect(reloaded).to have_received(:handle).once
      expect(subscribed).not_to have_received(:handle)
    end
  end

  context 'when code reloading loads the model again without the subscription' do
    before do
      Artery.unregister_model(item)
      Artery.register_model(item)
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands messages to none of its previous subscriptions' do
      expect(subscribed).not_to have_received(:handle)
    end
  end

  context 'when code reloading loads the model again before it is named' do
    before do
      Artery.unregister_model(item)
      allow(item).to receive(:name).and_return(nil)
      Artery.register_model(item)
      allow(item).to receive(:name).and_return('Item')
      Artery.add_subscription(reloaded)
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands messages to its new subscriptions only', :aggregate_failures do
      expect(reloaded).to have_received(:handle).once
      expect(subscribed).not_to have_received(:handle)
    end
  end

  context 'when code reloading unloads once more the model loaded again before it was named' do
    before do
      Artery.unregister_model(item)
      allow(item).to receive(:name).and_return(nil)
      Artery.register_model(item)
      allow(item).to receive(:name).and_return('Item')
      Artery.add_subscription(reloaded)
      Artery.unregister_model(item)
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands messages to the subscriptions it had last', :aggregate_failures do
      expect(reloaded).to have_received(:handle).once
      expect(subscribed).not_to have_received(:handle)
    end
  end

  context 'when code reloading unloads the model loaded again' do
    before do
      Artery.unregister_model(item)
      Artery.register_model(item)
      Artery.add_subscription(reloaded)
      Artery.unregister_model(item)
      callbacks['test.items.new'].call('{}', nil, 'test.items.new')
    end

    it 'hands messages to the subscriptions it had last', :aggregate_failures do
      expect(reloaded).to have_received(:handle).once
      expect(subscribed).not_to have_received(:handle)
    end
  end
end
