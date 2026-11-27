# frozen_string_literal: true

describe Artery::Backends::NATSPure::ErrorReporter do
  subject(:reporter) { described_class.new }

  let(:release) { Concurrent::Event.new }
  let(:logger) { instance_double(Logger, error: nil) }

  before do
    stub_const("#{described_class}::QUEUE_SIZE", 1)
    allow(Artery).to receive(:logger).and_return(logger)
    reporter.post { release.wait(5) }
    reporter.post { nil }
  end

  after do
    release.set
    reporter.shutdown
  end

  context 'when more reports are pending than the queue holds' do
    before do
      reporter.post { nil }
      release.set
      reporter.shutdown
    end

    it 'logs how many it dropped' do
      expect(logger).to have_received(:error).with(/1 NATS error report\(s\) dropped/)
    end
  end

  context 'when the pending reports are not done in time on stopping' do
    before do
      reporter.shutdown(0.1)
    end

    it 'logs that they are lost' do
      expect(logger).to have_received(:error).with(/not done 0.1 s after stopping/)
    end
  end
end
