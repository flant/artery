# frozen_string_literal: true

RSpec.describe Artery::ActiveRecord::ModelInfo do
  describe '.acquire_lock!' do
    context 'when no lock row exists' do
      it 'creates a new row and returns it' do
        expect { described_class.acquire_lock!(:source) }
          .to change(described_class, :count).by(1)

        row = described_class.find_by(model: 'source')
        expect(row).to be_present
        expect(row.latest_index).to eq(0)
      end

      it 'sets latest_index from existing artery_messages' do
        create(:source)
        last_message = Artery.message_class.last

        row = described_class.acquire_lock!(:source)
        expect(row.latest_index).to eq(last_message.id)
      end
    end

    context 'when lock row already exists' do
      before { described_class.create!(model: 'source', latest_index: 42) }

      it 'returns the existing row without creating a new one' do
        expect { described_class.acquire_lock!(:source) }
          .not_to change(described_class, :count)

        row = described_class.acquire_lock!(:source)
        expect(row.latest_index).to eq(42)
      end
    end
  end
end
