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

  describe '.ensure_initialized!' do
    context 'when no row exists' do
      it 'creates a new row' do
        expect { described_class.ensure_initialized!(:source) }
          .to change(described_class, :count).by(1)
      end

      it 'sets latest_index from existing messages' do
        create(:source)
        last_message = Artery.message_class.last

        described_class.where(model: 'source').delete_all

        row = described_class.ensure_initialized!(:source)
        expect(row.latest_index).to eq(last_message.id)
      end
    end

    context 'when row exists with zero last_published_id' do
      before do
        create(:source)
        described_class.find_by(model: 'source')&.destroy
        described_class.create!(model: 'source', latest_index: 5, last_published_id: 0)
      end

      it 'initializes last_published_id from latest_index' do
        row = described_class.ensure_initialized!(:source)
        expect(row.last_published_id).to eq(5)
      end
    end

    context 'when row exists with non-zero last_published_id' do
      before do
        described_class.create!(model: 'source', latest_index: 10, last_published_id: 8)
      end

      it 'does not change last_published_id' do
        row = described_class.ensure_initialized!(:source)
        expect(row.last_published_id).to eq(8)
      end
    end
  end
end
