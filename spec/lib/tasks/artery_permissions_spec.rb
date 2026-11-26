# frozen_string_literal: true

require 'rake'

describe 'artery:permissions', type: :task do
  subject(:task) { Rake::Task['artery:permissions'] }

  let(:entry) do
    a_string_including('"user": "test_nats"', '"password": $TEST_NATS',
                       '"test.source.*"', '"_INBOX.test.>"')
  end

  around do |example|
    env = ENV.to_h
    application = Rake.application
    ENV.delete('ARTERY_INBOX_PREFIX')
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = application
    ENV.replace(env)
  end

  before do
    Rails.application.load_tasks
  end

  it 'prints the user entry of the dummy application' do
    expect { task.invoke('TEST_NATS', 'test_nats') }.to output(entry).to_stdout
  end
end
