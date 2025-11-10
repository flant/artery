# frozen_string_literal: true

RSpec.describe Recipient do
  let(:source) { create(:source) }

  # before { Thread.new { Artery::Worker.new.run } }

  describe '.artery' do
    subject(:artery) { described_class.artery }

    it do
      expect(artery).to match(
        {
          source: false,
          name: :recipient,
          uuid_attribute: :uuid,
          subscriptions: [an_instance_of(Artery::Subscription)],
          representations: { _default: be_a(Proc) }
        }
      )
    end

    describe 'subscription' do
      subject(:subscription) { artery[:subscriptions].first }

      it do
        expect(subscription.latest_message_index).to be(0)
        expect(subscription.latest_outgoing_message_index).to be_nil
      end
    end
  end

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
