# frozen_string_literal: true

describe Artery, '.models' do
  subject(:models) { described_class.models }

  let(:previous_charge) { class_double(Source, name: 'Archive::Charge') }
  let(:reloaded_charge) { class_double(Source, name: 'Archive::Charge') }

  after do
    described_class.unregister_model('Archive::Charge')
  end

  it { is_expected.to include(Source, Recipient) }

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
      described_class.unregister_model('Archive::Charge')
    end

    it { is_expected.not_to include(previous_charge) }
  end
end
