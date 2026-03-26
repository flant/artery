# frozen_string_literal: true

RSpec.describe Source do
  let(:source) { create(:source) }

  describe '.artery' do
    subject(:artery) { described_class.artery }

    it do
      expect(artery).to match(
        {
          source: true,
          name: :source,
          uuid_attribute: :uuid,
          subscriptions: [
            an_instance_of(Artery::Subscription),
            an_instance_of(Artery::Subscription),
            an_instance_of(Artery::Subscription)
          ],
          representations: { _default: be_a(Proc) }
        }
      )
    end

    describe 'subscription' do
      subject(:subscription) { artery[:subscriptions].first }

      it do
        expect(subscription.latest_message_index).to be(0)
        expect(subscription.latest_outgoing_message_index).to be(0)
      end

      context 'when message queue is not empty' do
        before { source }

        it do
          expect(subscription.latest_message_index).to be(0)
          expect(subscription.latest_outgoing_message_index).to be(1)
        end
      end
    end
  end

  context 'when creating' do
    it 'creates Artery::Message' do
      source
      expect(Artery.message_class.count).to eq(1)
      expect(Artery.message_class.first.action).to eq('create')
      expect(Artery.message_class.first.data['uuid']).to eq(source.uuid)
    end

    it 'pushes message to backend' do
      received = nil
      Artery.subscribe('test.source.create') { |m| received = m }

      source

      sleep 0.1

      expect(received).to be_present
      expect(received['uuid']).to eq(source.uuid)
    end
  end

  context 'when updating' do
    it 'creates Artery::Message' do
      source.update! name: 'new'
      expect(Artery.message_class.count).to eq(2)
      expect(Artery.message_class.last.action).to eq('update')
      expect(Artery.message_class.last.data['uuid']).to eq(source.uuid)
    end

    it 'pushes message to backend' do
      received = nil
      Artery.subscribe('test.source.update') { |m| received = m }
      source.update! name: 'new'

      sleep 0.1

      expect(received).to be_present
      expect(received['uuid']).to eq(source.uuid)
    end
  end

  context 'when destroying' do
    it 'creates Artery::Message' do
      source.destroy
      expect(Artery.message_class.count).to eq(2)
      expect(Artery.message_class.last.action).to eq('delete')
      expect(Artery.message_class.last.data['uuid']).to eq(source.uuid)
    end

    it 'pushes message to backend' do
      received = nil
      Artery.subscribe('test.source.delete') { |m| received = m }
      source.destroy

      sleep 0.1

      expect(received).to be_present
      expect(received['uuid']).to eq(source.uuid)
    end
  end

  describe 'deferred callbacks' do
    it 'does not create artery messages on rollback' do
      expect do
        described_class.transaction do
          described_class.create!(uuid: Faker::Internet.uuid, name: 'rollback')
          raise ActiveRecord::Rollback
        end
      end.not_to change(Artery.message_class, :count)
    end

    it 'creates multiple artery messages for create+update in one transaction' do
      s = nil
      described_class.transaction do
        s = described_class.create!(uuid: Faker::Internet.uuid, name: 'original')
        s.update!(name: 'updated')
      end

      messages = Artery.message_class.where(model: 'source').order(:id)
      expect(messages.map(&:action)).to eq(%w[create update])
      expect(messages.map { |m| m.data['uuid'] }.uniq).to eq([s.uuid])
    end
  end

  describe 'non_atomic_notification mode' do
    let(:deferred_source_class) do
      Class.new(ApplicationRecord) do
        self.table_name = 'sources'
        extend Artery::Model
        artery_model source: true, non_atomic_notification: true, name: :deferred_source
      end
    end

    it 'registers after_commit instead of before_commit' do
      callbacks = deferred_source_class._commit_callbacks.map { |cb| cb.filter.to_s }
      expect(callbacks).to include('artery_send_pending_notifications')

      before_commit_callbacks = deferred_source_class._before_commit_callbacks.map { |cb| cb.filter.to_s }
      expect(before_commit_callbacks).not_to include('artery_send_pending_notifications')
    end

    it 'creates artery messages on create' do
      expect do
        deferred_source_class.create!(uuid: Faker::Internet.uuid, name: 'deferred')
      end.to change(Artery.message_class, :count).by(1)

      expect(Artery.message_class.last.action).to eq('create')
    end

    it 'creates artery messages with correct previous_index chain' do
      deferred_source_class.create!(uuid: Faker::Internet.uuid, name: 'first')
      deferred_source_class.create!(uuid: Faker::Internet.uuid, name: 'second')

      messages = Artery.message_class.where(model: 'deferred_source').order(:id).to_a
      expect(messages.size).to eq(2)
      expect(messages[0].previous_index).to eq(0)
      expect(messages[1].previous_index).to eq(messages[0].id)
    end

    it 'retries on failure and eventually succeeds' do
      call_count = 0
      allow(Artery.message_class).to receive(:create!).and_wrap_original do |m, **args|
        call_count += 1
        raise StandardError, 'transient error' if call_count <= 2

        m.call(**args)
      end

      expect do
        deferred_source_class.create!(uuid: Faker::Internet.uuid, name: 'retry-test')
      end.to change(Artery.message_class, :count).by(1)

      expect(call_count).to eq(3)
    end

    it 'reports error after exhausting retries' do
      allow(Artery.message_class).to receive(:create!).and_raise(StandardError, 'persistent error')
      allow(Artery).to receive(:handle_error)

      deferred_source_class.create!(uuid: Faker::Internet.uuid, name: 'fail-test')

      expect(Artery).to have_received(:handle_error).with(
        an_instance_of(Artery::Error).and(having_attributes(message: /persistent error/))
      )
    end
  end

  describe 'Backend _previous_index payload' do
    it 'publishes correct _previous_index for sequential messages' do
      received = []
      Artery.subscribe('test.source.create') { |m| received << m }

      create(:source)
      create(:source)

      sleep 0.2

      expect(received.size).to eq(2)
      expect(received[0]['_previous_index']).to eq(0)
      expect(received[1]['_previous_index']).to eq(received[0]['_index'])
    end
  end
end
