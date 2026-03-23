# frozen_string_literal: true

describe Artery::Instrumentation do
  it 'fires an ActiveSupport::Notifications event with the artery namespace' do
    events = []
    ActiveSupport::Notifications.subscribe('test_event.artery') do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    described_class.instrument(:test_event, foo: :bar)

    expect(events.size).to eq(1)
    expect(events.first.payload).to eq(foo: :bar)
  ensure
    ActiveSupport::Notifications.unsubscribe('test_event.artery')
  end

  it 'passes through the block and measures duration' do
    events = []
    ActiveSupport::Notifications.subscribe('timed.artery') do |*args|
      events << ActiveSupport::Notifications::Event.new(*args)
    end

    result = described_class.instrument(:timed, route: 'x') { 42 }

    expect(result).to eq(42)
    expect(events.size).to eq(1)
    expect(events.first.duration).to be >= 0
  ensure
    ActiveSupport::Notifications.unsubscribe('timed.artery')
  end
end
