# frozen_string_literal: true

RSpec.describe Artery::Publisher do
  subject(:publisher) { described_class.new }

  describe '#publish_batch (via send)' do
    let(:model_name) { 'source' }

    before do
      Artery::ActiveRecord::ModelInfo.find_or_create_by!(model: model_name) do |r|
        r.latest_index = 0
        r.last_published_id = 0
      end
    end

    it 'returns 0 when no unpublished messages exist' do
      result = publisher.send(:publish_batch, model_name)
      expect(result).to eq(0)
    end

    it 'publishes messages and advances last_published_id' do
      create(:source)
      create(:source)
      messages = Artery.message_class.where(model: model_name).order(:id).to_a

      received = []
      Artery.subscribe('test.source.create') { |m| received << m }

      result = publisher.send(:publish_batch, model_name)

      sleep 0.2

      expect(result).to eq(2)
      expect(received.size).to eq(2)

      row = Artery::ActiveRecord::ModelInfo.find_by!(model: model_name)
      expect(row.last_published_id).to eq(messages.last.id)
    end

    it 'builds correct _previous_index chain' do
      3.times { create(:source) }
      messages = Artery.message_class.where(model: model_name).order(:id).to_a

      received = []
      Artery.subscribe('test.source.create') { |m| received << m }

      publisher.send(:publish_batch, model_name)

      sleep 0.2

      expect(received.size).to eq(3)
      expect(received[0]['_previous_index']).to eq(0)
      expect(received[1]['_previous_index']).to eq(messages[0].id)
      expect(received[2]['_previous_index']).to eq(messages[1].id)
    end

    it 'resumes from last_published_id on subsequent calls' do
      create(:source)
      publisher.send(:publish_batch, model_name)

      create(:source)
      first_message = Artery.message_class.where(model: model_name).order(:id).first

      received = []
      Artery.subscribe('test.source.create') { |m| received << m }

      publisher.send(:publish_batch, model_name)

      sleep 0.2

      expect(received.size).to eq(1)
      expect(received[0]['_previous_index']).to eq(first_message.id)
    end
  end
end
