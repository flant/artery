# frozen_string_literal: true

RSpec.describe Recipient, '#artery_rewind_message_counter!' do
  subject(:rewind) { described_class.artery_rewind_message_counter!(service: :test) }

  let(:subscription) do
    described_class.artery[:subscriptions].detect do |sub|
      sub.uri.service.to_sym == :test && sub.synchronize_updates?
    end
  end

  let!(:subscription_info) do
    subscription.info.tap { |info| info.update!(latest_index: local_index) }
  end

  let(:local_index) { 1_000 }
  let(:remote_index) { 500 }
  let(:route) { 'test.sources.get_all' }

  before do
    allow(Artery).to receive(:request) do |requested_route, _params = {}, &block|
      handler = Multiblock.wrapper
      block.call(handler)

      if requested_route == route
        handler.call(:success, { _index: remote_index, objects: [] })
      else
        handler.call(:error, Artery::Error.new("unexpected route #{requested_route}"))
      end
    end
  end

  around do |example|
    clear_subscription_info_memo!
    example.run
  ensure
    clear_subscription_info_memo!
  end

  def clear_subscription_info_memo!
    described_class.artery[:subscriptions]&.each do |sub|
      described_class.artery[:subscriptions]&.each(&:reset_info!)
    end
  end

  context 'when local index is ahead of the publisher' do
    it 'rewinds the subscription index' do
      expect(rewind).to be(true)
      expect(Artery).to have_received(:request).with(
        route,
        hash_including(page: 0, per_page: 1)
      )
      expect(subscription_info.reload.latest_index).to eq(remote_index)
    end
  end

  context 'when local index is not ahead of the publisher' do
    let(:remote_index) { 1_500 }

    it 'keeps the local index' do
      expect(rewind).to be(true)
      expect(subscription_info.reload.latest_index).to eq(local_index)
    end
  end

  context 'when remote index is zero' do
    let(:remote_index) { 0 }

    it 'does not rewind to zero' do
      expect(rewind).to be(true)
      expect(subscription_info.reload.latest_index).to eq(local_index)
    end
  end

  context 'when publisher request fails' do
    before do
      allow(Artery).to receive(:request) do |_route, *_args, &block|
        handler = Multiblock.wrapper
        block.call(handler)
        handler.call(:error, Artery::Error.new('timeout'))
      end
    end

    it 'raises' do
      expect { rewind }.to raise_error(Artery::Error, /Failed to fetch artery index/)
    end
  end

  context 'when called on a source model' do
    it 'returns false' do
      expect(Source.artery_rewind_message_counter!(service: :test)).to be(false)
    end
  end

  context 'when service does not match any subscription' do
    subject(:rewind) { described_class.artery_rewind_message_counter!(service: :other) }

    it 'returns false without requesting' do
      expect(rewind).to be(false)
      expect(Artery).not_to have_received(:request)
    end
  end
end
