# frozen_string_literal: true

require 'open3'

describe Artery::Backends::Fake do
  subject(:backend) { described_class.new(config) }

  let(:config) { {} }
  let(:replies) { [] }

  before do
    allow(Artery).to receive(:backend) { backend }
  end

  def request(route)
    Artery.request(route) do |on|
      on.success { |data| replies << data }
      on.error { |error| replies << error }
    end
  end

  context 'without a prepared reply' do
    before do
      request('bush.permission.effective_permissions')
    end

    it 'replies with an empty message' do
      expect(replies).to eq([{}])
    end
  end

  context 'with a prepared reply' do
    before do
      backend.reply('bush.permission.effective_permissions', permissions: %w[read])
      request('bush.permission.effective_permissions')
    end

    it 'hands it to the requester' do
      expect(replies).to eq([{ 'permissions' => %w[read] }])
    end
  end

  context 'with a prepared timeout' do
    before do
      backend.time_out('bush.permission.effective_permissions')
      request('bush.permission.effective_permissions')
    end

    it 'times the request out' do
      expect(replies).to contain_exactly(an_instance_of(Artery::TimeoutError))
    end
  end

  context 'when the replies are cleared' do
    before do
      backend.reply('bush.permission.effective_permissions', permissions: %w[read])
      backend.clear_replies
      request('bush.permission.effective_permissions')
    end

    it 'replies with an empty message again' do
      expect(replies).to eq([{}])
    end
  end

  context 'when the service publishes to a subject without permission' do
    it 'does not check it' do
      expect { Artery.publish('the_new_run.issues.new', {}) }.not_to raise_error
    end
  end

  context 'with strict permissions' do
    let(:config) { { strict_permissions: true } }

    context 'when it requests a route it has not declared' do
      before do
        backend.reply('bush.permission.effective_permissions', permissions: %w[read])
      end

      it 'fails before the prepared reply is returned' do
        expect { request('bush.permission.effective_permissions') }.to raise_error(
          Artery::PermissionDenied,
          'test has no permission to publish to bush.permission.effective_permissions: ' \
          'declare the routes it requests or publishes directly with Artery.add_outgoing_routes'
        )
      end
    end

    context 'when it requests a declared route' do
      before do
        allow(Artery).to receive(:outgoing_routes).and_return(%w[bush.permission.effective_permissions])
        backend.reply('bush.permission.effective_permissions', permissions: %w[read])
        request('bush.permission.effective_permissions')
      end

      it 'hands the prepared reply to the requester' do
        expect(replies).to eq([{ 'permissions' => %w[read] }])
      end
    end

    context 'when it publishes to a route it has not declared' do
      it 'fails' do
        expect { Artery.publish('the_new_run.issues.new', {}) }.to raise_error(Artery::PermissionDenied, /publish/)
      end
    end

    context 'when it answers a request' do
      it 'publishes to the inbox of the requester' do
        expect { Artery.publish('_INBOX.bush.abc.1', {}) }.not_to raise_error
      end
    end

    context 'when it subscribes to a route of a model subscription' do
      it 'subscribes' do
        expect { backend.subscribe('test.source.*') }.not_to raise_error
      end
    end

    context 'when it subscribes to a route of no subscription' do
      it 'fails with a hint' do
        expect { backend.subscribe('bush.users.*') }.to raise_error(Artery::PermissionDenied, /artery_watch_model/)
      end
    end

    context 'when it checks permissions again' do
      before do
        allow(Artery::Permissions).to receive(:load_application)
        backend.publish('test.healthz.check')
        backend.publish('test.healthz.check')
      end

      it 'loads the application once' do
        expect(Artery::Permissions).to have_received(:load_application).once
      end
    end

    context 'without a service name' do
      before do
        allow(Artery).to receive(:service_name?).and_return(false)
      end

      it 'fails when the backend is set up' do
        expect { backend }.to raise_error(Artery::Error, /need Artery.service_name/)
      end
    end
  end

  context 'with ARTERY_STRICT_PERMISSIONS=1' do
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('ARTERY_STRICT_PERMISSIONS', nil).and_return('1')
    end

    it { is_expected.to be_strict_permissions }
  end

  # A separate process, so the models are loaded only by the strict backend itself.
  context 'when the model of a subscription is not loaded yet' do
    subject do
      Open3.capture2({ 'RAILS_ENV' => 'test', 'ARTERY_STRICT_PERMISSIONS' => '1' }, RbConfig.ruby, '-e', script,
                     chdir: Rails.root.to_s)
    end

    let(:script) do
      <<~RUBY
        require './config/environment'
        Artery.use_backend :fake
        Artery.backend.subscribe('test.source.*')
        print Object.const_defined?(:Recipient, false) ? 'loaded' : 'not loaded'
      RUBY
    end

    it { is_expected.to match(['loaded', be_success]) }
  end
end
