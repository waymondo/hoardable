# frozen_string_literal: true

module Hoardable
  # A subclass of +StandardError+ for general use within {Hoardable}.
  class Error < StandardError
  end

  # An error to be raised when 'created_at' columns are missing for {Hoardable::Model}s.
  class CreatedAtColumnMissingError < Error
    def initialize(source_table_name)
      super(<<~LOG)
          '#{source_table_name}' does not have a 'created_at' column, so the start of the first
          version’s temporal period cannot be known. Add a 'created_at' column to '#{source_table_name}'.
        LOG
    end
  end

  # An error to be raised when 'updated_at' columns are missing for {Hoardable::Model}s.
  class UpdatedAtColumnMissingError < Error
    def initialize(source_table_name)
      super(<<~LOG)
          '#{source_table_name}' does not have an 'updated_at' column, so Hoardable cannot look up
          associated record versions with it. Add an 'updated_at' column to '#{source_table_name}'.
        LOG
    end
  end

  # An error to be raised when the provided temporal upper bound is before the calcualated lower bound.
  class InvalidTemporalUpperBoundError < Error
    def initialize(upper, lower)
      super(<<~LOG)
          'The supplied value to `Hoardable.on` (#{upper}) is before the calculated lower bound (#{lower}).
          You must provide a datetime > the lower bound.
        LOG
    end
  end
end
