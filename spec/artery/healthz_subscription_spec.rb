# frozen_string_literal: true

describe Artery::HealthzSubscription do
  before do
    described_class.new.subscribe
  end

  it 'answers with ok' do
    resp = nil
    Artery.request("#{Artery.service_name}.healthz.check") do |on|
      on.success do |r|
        resp = r
      end
    end

    expect(resp['status']).to eq('ok')
  end
end
