# frozen_string_literal: true

describe Artery::Subscription, '#requested_routes' do
  subject { described_class.new(class_double(Recipient), uri, handler: handler, **options).requested_routes }

  let(:handler) { instance_double(Multiblock::Wrapper) }
  let(:handled_action) { :create }
  let(:uri) { Artery::Routing.uri(service: :bush, model: :user, action: '*') }
  let(:options) { { synchronize: true } }

  before do
    allow(Artery).to receive(:add_subscription)
    allow(handler).to receive(:has_block?).and_return(false)
    allow(handler).to receive(:has_block?).with(handled_action).and_return(true)
  end

  context 'when it watches every action of another service and synchronizes' do
    it { is_expected.to eq(%w[bush.users.get bush.users.get_updates bush.users.get_all]) }
  end

  context 'when it handles only deletions of every action' do
    let(:handled_action) { :delete }
    let(:options) { { synchronize_updates: false } }

    it { is_expected.to be_empty }
  end

  context 'when it watches one action and receives updates' do
    let(:uri) { Artery::Routing.uri(service: :bush, model: :user, action: :delete) }
    let(:handled_action) { :_default }
    let(:options) { {} }

    it { is_expected.to eq(%w[bush.users.get bush.users.get_updates]) }
  end

  context 'when it is a client that receives updates' do
    let(:options) { { client: true } }

    it { is_expected.to include('bush.users.get_all') }
  end

  context 'when it watches the service itself' do
    let(:uri) { Artery::Routing.uri(model: :source, action: '*') }
    let(:options) { {} }

    it { is_expected.to eq(%w[test.sources.get]) }
  end
end
