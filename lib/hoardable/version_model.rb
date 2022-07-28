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
      scope :at, ->(datetime) { where(DURING_QUERY, datetime) }
    end

    def revert!
      raise(Error, 'Version is trashed, cannot revert') unless _operation == 'update'

      transaction do
        hoardable_source.tap do |reverted|
          reverted.update!(hoardable_source_attributes.without('id'))
          reverted.instance_variable_set(:@hoardable_version, self)
          reverted.run_callbacks(:reverted)
        end
      end
    end

    def untrash!
      raise(Error, 'Version is not trashed, cannot untrash') unless _operation == 'delete'

      transaction do
        superscope = self.class.superclass.unscoped
        superscope.insert(untrashable_hoardable_source_attributes)
        superscope.find(hoardable_source_foreign_id).tap do |untrashed|
          untrashed.instance_variable_set(:@hoardable_version, self)
          untrashed.run_callbacks(:untrashed)
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

    def untrashable_hoardable_source_attributes
      hoardable_source_attributes.merge('id' => hoardable_source_foreign_id).tap do |hash|
        hash['updated_at'] = Time.now if self.class.column_names.include?('updated_at')
      end
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

    def hoardable_source_foreign_id
      @hoardable_source_foreign_id ||= public_send(hoardable_source_foreign_key)
    end

    def previous_temporal_tsrange_end
      hoardable_source.versions.limit(1).order(_during: :desc).pluck('_during').first&.end
    end

    def assign_temporal_tsrange
      self._during = ((previous_temporal_tsrange_end || hoardable_source.created_at)..Time.now)
    end
  end
end
