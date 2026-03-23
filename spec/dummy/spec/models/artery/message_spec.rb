# frozen_string_literal: true

RSpec.describe Artery::ActiveRecord::Message do
  describe 'previous_index chain' do
    it 'forms a correct chain across sequential creates' do
      Array.new(3) { create(:source) }
      messages = described_class.where(model: 'source').order(:id).to_a

      expect(messages.size).to eq(3)
      expect(messages[0].previous_index).to eq(0)
      expect(messages[1].previous_index).to eq(messages[0].id)
      expect(messages[2].previous_index).to eq(messages[1].id)
    end
  end

  describe '#cached_previous_index' do
    it 'is used by previous_index when set' do
      message = described_class.new
      message.cached_previous_index = 42

      expect(message.previous_index).to eq(42)
    end

    it 'falls back to DB query when not set' do
      create(:source)
      message = described_class.last

      expect(message.cached_previous_index).to be_nil
      expect(message.previous_index).to eq(0)
    end
  end

  describe '.latest_index' do
    it 'returns 0 when no messages exist' do
      expect(described_class.latest_index(:source)).to eq(0)
    end

    it 'returns the id of the last message after creates' do
      create(:source)
      last_message = described_class.last

      expect(described_class.latest_index(:source)).to eq(last_message.id)
    end

    it 'matches the value stored in ModelInfo' do
      create(:source)
      last_message = described_class.last

      model_info = Artery::ActiveRecord::ModelInfo.find_by(model: 'source')
      expect(model_info.latest_index).to eq(last_message.id)
      expect(described_class.latest_index(:source)).to eq(model_info.latest_index)
    end
  end
end
