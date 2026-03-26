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

  describe '.latest_index' do
    it 'returns 0 when no messages exist' do
      expect(described_class.latest_index(:source)).to eq(0)
    end

    it 'returns the id of the last message after creates' do
      create(:source)
      last_message = described_class.last

      expect(described_class.latest_index(:source)).to eq(last_message.id)
    end

    it 'queries directly from artery_messages table' do
      create(:source)
      last_message = described_class.last

      expect(described_class.latest_index(:source)).to eq(last_message.id)
      expect(described_class.latest_index(:nonexistent)).to eq(0)
    end
  end

  describe '#publish_to_artery' do
    it 'publishes message with given previous_index' do
      create(:source)
      message = described_class.last

      received = nil
      Artery.subscribe(message.route) { |m| received = m }

      message.publish_to_artery(previous_index: 42)

      sleep 0.1

      expect(received).to be_present
      expect(received['_index']).to eq(message.id)
      expect(received['_previous_index']).to eq(42)
    end
  end
end
