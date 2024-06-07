# frozen_string_literal: true

module Multiblock
  module HasBlock
    def has_block?(block_name)
      @blocks.key?(block_name.to_s)
    end
  end
end

Multiblock::Wrapper.include Multiblock::HasBlock
