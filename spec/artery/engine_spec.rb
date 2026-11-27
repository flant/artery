# frozen_string_literal: true

describe Artery::Engine do
  context 'with Zeitwerk without on_unload' do
    subject { Artery.models }

    let(:loader) { instance_double(Zeitwerk::Loader, unloadable_cpaths: ['Archive::Charge']) }
    let(:reloader) { class_double(ActiveSupport::Reloader) }
    let(:charge) { class_double(Source, name: 'Archive::Charge') }
    let(:hooks) { [] }

    before do
      stub_const('Archive::Charge', charge)
      allow(Rails).to receive(:autoloaders).and_return(instance_double(Rails::Autoloaders, main: loader))
      allow(reloader).to receive(:before_class_unload) { |&hook| hooks << hook }
      Artery.register_model(charge)
      described_class.initializers.find { |initializer| initializer.name == 'artery.models_reloading' }
                     .run(instance_double(Rails::Application, reloader: reloader))
      hooks.each(&:call)
    end

    after do
      Artery.unregister_model(charge)
    end

    it { is_expected.not_to include(charge) }
  end
end
