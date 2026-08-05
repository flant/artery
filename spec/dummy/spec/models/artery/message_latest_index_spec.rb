# frozen_string_literal: true

RSpec.describe Artery::ActiveRecord::Message, '.latest_index' do
  describe 'when artery_messages is empty but model_infos has last_published_id' do
    before do
      Artery.model_info_class.create!(
        model: 'source',
        latest_index: 0,
        last_published_id: 10_000
      )
    end

    it 'returns last_published_id' do
      expect(described_class.latest_index(:source)).to eq(10_000)
    end
  end

  describe 'when both messages and last_published_id exist' do
    before do
      create(:source)
      Artery.model_info_class.find_or_create_by!(model: 'source') do |row|
        row.latest_index = 0
        row.last_published_id = 1
      end.tap do |row|
        # last_published_id behind the newest message id
        row.update!(last_published_id: 1)
      end
    end

    it 'returns the greater of max(message id) and last_published_id' do
      last_message_id = described_class.where(model: 'source').maximum(:id).to_i

      expect(described_class.latest_index(:source)).to eq([last_message_id, 1].max)
      expect(described_class.latest_index(:source)).to eq(last_message_id)
    end
  end

  describe 'when neither messages nor model_info exist' do
    it 'returns 0' do
      expect(described_class.latest_index(:nonexistent)).to eq(0)
    end
  end
end
