# frozen_string_literal: true

describe Artery, '.outgoing_routes' do
  subject { described_class.outgoing_routes }

  around do |example|
    routes = described_class.outgoing_routes.dup
    example.run
  ensure
    described_class.outgoing_routes.replace(routes)
  end

  before do
    described_class.add_outgoing_routes('madison.events.new', Artery::Routing.uri('bush.contacts.external_create'))
    described_class.add_outgoing_routes(%w[license.licenses.daas_tokens])
  end

  it { is_expected.to include('madison.events.new', 'bush.contacts.external_create', 'license.licenses.daas_tokens') }
end
