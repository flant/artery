# frozen_string_literal: true

describe Artery::Backends::NATSPure, '#auth_user' do
  subject { described_class.new(config).auth_user }

  let(:config) { { user: 'billing', password: 'secret' } }

  around do |example|
    env = ENV.to_h
    ENV.delete('NATS_URL')
    example.run
  ensure
    ENV.replace(env)
  end

  it { is_expected.to eq('billing') }

  context 'with a token configured as the user' do
    let(:config) { { user: 's3cr3t-token' } }

    it { is_expected.to be_nil }
  end

  context 'with the credentials in the server address' do
    let(:config) { { servers: ['nats://billing:secret@nats:4222'] } }

    it { is_expected.to eq('billing') }
  end

  context 'with the user in the server address and the password configured' do
    let(:config) { { servers: ['nats://billing@nats:4222'], password: 'secret' } }

    it { is_expected.to eq('billing') }
  end

  context 'with the credentials in NATS_URL' do
    let(:config) { {} }

    before do
      ENV['NATS_URL'] = 'nats://billing:secret@nats:4222'
    end

    it { is_expected.to eq('billing') }
  end
end
