# frozen_string_literal: true

module Hoardable
  # A subclass of +StandardError+ for general use within {Hoardable}.
  class Error < StandardError; end

  class CreatedAtColumnMissingError < Error
    def initialize(source_table_name)
      super(
        <<~LOG
          '#{source_table_name}' does not have a 'created_at' column, so the start of the first
          version’s temporal period cannot be known. Add a 'created_at' column to '#{source_table_name}'.
        LOG
      )
    end
  end
end
