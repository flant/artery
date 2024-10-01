# frozen_string_literal: true

RSpec.describe Recipient do
  let(:source) { create(:source) }

  # before { Thread.new { Artery::Worker.new.run } }

  xcontext 'when source created' do
    it 'creates recipient' do
      source

      sleep 0.2

      expect(described_class.count).to eq(1)
      expect(described_class.first.uuid).to eq(source.uuid)
    end
  end

  xcontext 'when updating' do
  end

  xcontext 'when destroying' do
  end
end
