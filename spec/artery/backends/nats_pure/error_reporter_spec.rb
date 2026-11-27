# frozen_string_literal: true

describe Artery::Backends::NATSPure::ErrorReporter do
  subject(:reporter) { described_class.new }

  let(:release) { Concurrent::Event.new }
  let(:logger) { instance_double(Logger, error: nil) }

  before do
    stub_const("#{described_class}::QUEUE_SIZE", 1)
    allow(Artery).to receive(:logger).and_return(logger)
  end

  after do
    release.set
    reporter.shutdown
  end

  context 'when more reports are pending than the queue holds' do
    before do
      reporter.post('first') { release.wait(5) }
      reporter.post('second') { nil }
      reporter.post('third') { nil }
    end

    it 'logs the report it drops' do
      expect(logger).to have_received(:error).with(/not reported, too many reports are pending/)
    end
  end
end
