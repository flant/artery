# frozen_string_literal: true

describe Artery::WorkerHealthzSubscription do
  let(:worker_id) { SecureRandom.hex }
  let(:worker_name) { 'worker' }

  before do
    described_class.new(worker_id, worker_name).subscribe
  end

  context 'with correct worker id' do
    it 'answers with ok' do
      resp = nil
      Artery.request("#{Artery.service_name}.healthz.#{worker_name}", { id: worker_id }, timeout: 0.5) do |on|
        on.success do |r|
          resp = r
        end
      end

      expect(resp&.dig('status')).to eq('ok')
    end
  end

  context 'with incorrect worker id' do
    # TODO: should not be TimeoutError ?
    it 'returns TimeoutError' do
      error = nil
      Artery.request("#{Artery.service_name}.healthz.#{worker_name}", { id: 'bad' }, timeout: 0.5) do |on|
        on.error do |e|
          error = e
        end
      end

      expect(error).to be_a(Artery::TimeoutError)
    end
  end
end
