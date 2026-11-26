# frozen_string_literal: true

require 'open3'

# A separate process, so the models are loaded only by the eager loading of the task itself.
describe 'artery:permissions', type: :task do
  subject do
    Open3.capture2({ 'RAILS_ENV' => 'test', 'ARTERY_INBOX_PREFIX' => nil },
                   RbConfig.ruby, '-S', 'rake', 'artery:permissions[TEST_NATS,test_nats]',
                   chdir: Rails.root.to_s).first
  end

  it { is_expected.to include('"user": "test_nats"', '"password": $TEST_NATS', '"test.source.*"', '"_INBOX.test.>"') }
end
