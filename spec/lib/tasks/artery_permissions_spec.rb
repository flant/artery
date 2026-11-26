# frozen_string_literal: true

require 'rake'

describe 'artery:permissions', type: :task do
  subject(:task) { Rake::Task['artery:permissions'] }

  let(:entry) do
    a_string_including('"user": "test"', '"password": $TEST_NATS', '"test.source.*"', '"test.sources.get_all"',
                       '"_INBOX.test.>"')
  end

  before do
    Rake::Task.clear
    Rails.application.load_tasks
  end

  it 'prints the user entry of the dummy application' do
    expect { task.invoke('TEST_NATS') }.to output(entry).to_stdout
  end
end
