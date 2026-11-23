# frozen_string_literal: true

RSpec.describe Artery::Subscription, '#synchronize!' do
  subject(:synchronize) { subscription.synchronize! }

  let(:subscription) { Recipient.artery[:subscriptions].detect(&:synchronize?) }
  let(:info) { subscription.info }
  let(:response) { ->(_handler) { raise NATS::IO::NoRespondersError } }

  before do
    # The dummy app watches its own service, and synchronize! skips the subscriptions of its own service.
    allow(Artery).to receive(:service_name).and_return(:other)
    allow(Artery).to receive(:handle_error)
    allow(Artery).to receive(:request) do |_route, _data = {}, &block|
      handler = Multiblock.wrapper
      block.call(handler)
      response.call(handler)
    end
  end

  around do |example|
    subscription.reset_info!
    example.run
  ensure
    subscription.send(:stop_synchronization_heartbeat)
    Artery.synchronizing_subscriptions.clear
    subscription.reset_info!
  end

  context 'when the request raises' do
    it 'clears the synchronization mark and raises' do
      expect { synchronize }.to raise_error(NATS::IO::NoRespondersError)

      expect(info.reload).to have_attributes(synchronization_in_progress: false, synchronization_heartbeat: nil)
      expect(Artery.synchronizing_subscriptions).not_to include(subscription)
    end

    it 'stops the heartbeat thread' do
      started = []
      allow(Thread).to receive(:new).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { |thread| started << thread }
      end

      expect { synchronize }.to raise_error(NATS::IO::NoRespondersError)

      expect(started).not_to be_empty
      expect(started.each { |thread| thread.join(1) }).to all(have_attributes(alive?: false))
    end
  end

  context 'when the synchronization is interrupted' do
    let(:response) { ->(_handler) { raise Interrupt } }

    it 'clears the synchronization mark and raises' do
      expect { synchronize }.to raise_error(Interrupt)

      expect(info.reload.synchronization_in_progress).to be(false)
    end
  end

  context 'when the request for updates raises' do
    before do
      info.update!(latest_index: 3)
      allow(subscription).to receive(:synchronize_updates?).and_return(true)
    end

    it 'clears the synchronization mark and raises' do
      expect { synchronize }.to raise_error(NATS::IO::NoRespondersError)

      expect(Artery).to have_received(:request).with('test.sources.get_updates', hash_including(after_index: 3))
      expect(info.reload).to have_attributes(synchronization_in_progress: false, latest_index: 3)
    end
  end

  context 'when nobody listens on the route' do
    let(:response) do
      lambda do |handler|
        handler.call(:error, Artery::NoRespondersError.new('No responders for test.sources.get_all'))
      end
    end

    it 'clears the synchronization mark and reports the failure' do
      synchronize

      expect(info.reload.synchronization_in_progress).to be(false)
      expect(Artery).to have_received(:handle_error).with(
        an_instance_of(Artery::Error).and(having_attributes(message: /No responders for test.sources.get_all/))
      )
    end
  end

  context 'when another process synchronizes the subscription' do
    let(:heartbeat) { 10.seconds.ago.change(usec: 0) }

    before { info.update!(synchronization_in_progress: true, synchronization_heartbeat: heartbeat) }

    it 'keeps the mark of that process' do
      expect { subscription.receive_all }.to raise_error(NATS::IO::NoRespondersError)

      expect(info.reload.synchronization_in_progress).to be(true)
      expect(info.synchronization_heartbeat).to eq(heartbeat)
    end
  end

  context 'when the next synchronization succeeds' do
    let(:responses) do
      [
        ->(_handler) { raise NATS::IO::NoRespondersError },
        ->(handler) { handler.call(:success, { _index: 5, objects: [] }) }
      ]
    end
    let(:response) { ->(handler) { responses.shift.call(handler) } }

    it 'synchronizes the subscription again' do
      expect { subscription.synchronize! }.to raise_error(NATS::IO::NoRespondersError)

      subscription.synchronize!

      expect(Artery).to have_received(:request).twice
      expect(info.reload).to have_attributes(synchronization_in_progress: false, latest_index: 5)
    end

    it 'starts a heartbeat thread for each synchronization' do
      started = []
      allow(Thread).to receive(:new).and_wrap_original do |original, *args, &block|
        original.call(*args, &block).tap { |thread| started << thread }
      end

      expect { subscription.synchronize! }.to raise_error(NATS::IO::NoRespondersError)
      subscription.synchronize!

      expect(started.size).to eq(2)
    end
  end
end
