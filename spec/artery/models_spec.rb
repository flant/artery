# frozen_string_literal: true

describe Artery, '.models' do
  subject(:models) { described_class.models }

  let!(:loaded_models) { [Source, Recipient] }
  let(:previous_charge) { class_double(Source, name: 'Archive::Charge') }
  let(:reloaded_charge) { class_double(Source, name: 'Archive::Charge') }

  after do
    described_class.unregister_model(reloaded_charge)
  end

  it { is_expected.to include(*loaded_models) }

  context 'when a model is loaded again' do
    before do
      described_class.register_model(previous_charge)
      described_class.register_model(reloaded_charge)
    end

    it 'keeps only the loaded class', :aggregate_failures do
      expect(models).to include(reloaded_charge)
      expect(models).not_to include(previous_charge)
    end
  end

  context 'when a model is unloaded' do
    before do
      described_class.register_model(previous_charge)
      described_class.unregister_model(previous_charge)
    end

    it { is_expected.not_to include(previous_charge) }
  end

  context 'when a model with subscriptions is unloaded' do
    subject(:subscriptions) { described_class.subscriptions }

    let(:subscription) { instance_double(Artery::Subscription, subscriber: previous_charge) }

    before do
      allow(described_class).to receive(:subscriptions)
        .and_return(Artery::Routing.uri('archive.charge.*') => [subscription])
      described_class.unregister_model(previous_charge)
    end

    it { is_expected.to be_empty }
  end
end
