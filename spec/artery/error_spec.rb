# frozen_string_literal: true

describe Artery::Error do
  let(:error_context) { { rialne: 1 } }

  it 'initializes with hash arguments' do
    error = described_class.new('pysh-pysh', **error_context, rialne: 'no')

    expect(error).to be_a(described_class)
    expect(error.artery_context).to match(rialne: 'no')
  end
end
