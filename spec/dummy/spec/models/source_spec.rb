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
end
