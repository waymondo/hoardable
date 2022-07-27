# frozen_string_literal: true

module Hoardable
  # This concern is included into the dynamically generated Version models.
  module VersionModel
    extend ActiveSupport::Concern

    included do
      hoardable_source_key = superclass.model_name.i18n_key
      belongs_to hoardable_source_key, inverse_of: :versions
      alias_method :hoardable_source, hoardable_source_key

      self.table_name = "#{table_name.singularize}#{Hoardable::VERSION_TABLE_SUFFIX}"

      alias_method :readonly?, :persisted?

      before_create :assign_temporal_tsrange

      scope :trashed, lambda {
        left_outer_joins(hoardable_source_key)
          .where(superclass.table_name => { id: nil })
          .where(_operation: 'delete')
      }
    end

    def revert!
      transaction do
        (
          hoardable_source&.tap { |tapped| tapped.update!(hoardable_source_attributes.without('id')) } ||
          untrash
        ).tap do |tapped|
          tapped.instance_variable_set(:@hoardable_version, self)
          tapped.run_callbacks(:reverted)
        end
      end
    end

    DATA_KEYS.each do |key|
      define_method("hoardable_#{key}") do
        _data&.dig(key.to_s)
      end
    end

    def changes
      _data&.dig('changes')
    end

    private

    def untrash
      foreign_id = public_send(hoardable_source_foreign_key)
      superscope = self.class.superclass.unscoped
      superscope.insert(hoardable_source_attributes.merge('id' => foreign_id, 'updated_at' => Time.now))
      superscope.find(foreign_id)
    end

    def hoardable_source_attributes
      @hoardable_source_attributes ||=
        attributes_before_type_cast
        .without(hoardable_source_foreign_key)
        .reject { |k, _v| k.start_with?('_') }
    end

    def hoardable_source_foreign_key
      @hoardable_source_foreign_key ||= "#{self.class.superclass.model_name.i18n_key}_id"
    end

    def previous_temporal_tsrange_end
      hoardable_source.versions.limit(1).order(_during: :desc).pluck('_during').first&.end
    end

    def assign_temporal_tsrange
      self._during = ((previous_temporal_tsrange_end || hoardable_source.created_at)..Time.now)
    end
  end
end
