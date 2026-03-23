# frozen_string_literal: true

describe Artery::Config do
  around do |example|
    saved = %i[@log_messages @message_body_max_size].to_h do |name|
      [name, { defined: Artery.instance_variable_defined?(name), value: Artery.instance_variable_get(name) }]
    end

    example.run
  ensure
    saved.each do |name, state|
      if state[:defined]
        Artery.instance_variable_set(name, state[:value])
      elsif Artery.instance_variable_defined?(name)
        Artery.remove_instance_variable(name)
      end
    end
  end

  describe '.log_messages?' do
    it 'defaults to true' do
      Artery.remove_instance_variable(:@log_messages) if Artery.instance_variable_defined?(:@log_messages)

      expect(Artery.log_messages?).to be true
    end

    it 'can be set to false' do
      Artery.log_messages = false

      expect(Artery.log_messages?).to be false
    end

    it 'can be set via configure block' do
      Artery.configure { |c| c.log_messages = false }

      expect(Artery.log_messages?).to be false
    end
  end

  describe '.message_body_max_size' do
    it 'defaults to nil (no truncation)' do
      if Artery.instance_variable_defined?(:@message_body_max_size)
        Artery.remove_instance_variable(:@message_body_max_size)
      end

      expect(Artery.message_body_max_size).to be_nil
    end

    it 'can be set to a custom value' do
      Artery.message_body_max_size = 2048

      expect(Artery.message_body_max_size).to eq(2048)
    end

    it 'can be set to nil for unlimited' do
      Artery.message_body_max_size = nil

      expect(Artery.message_body_max_size).to be_nil
    end

    it 'can be set to 0 via configure for unlimited' do
      Artery.configure { |c| c.message_body_max_size = 0 }

      expect(Artery.message_body_max_size).to eq(0)
    end
  end
end
