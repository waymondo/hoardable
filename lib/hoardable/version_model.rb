# frozen_string_literal: true

module Hoardable
  # This concern is included into the dynamically generated Version models.
  module VersionModel
    extend ActiveSupport::Concern

    included do
      # TODO: cast to / from ruby class
      # attribute :hoardable_data
      hoardable_source = superclass.model_name.i18n_key
      belongs_to hoardable_source, inverse_of: :versions
      alias_method :hoardable_source, hoardable_source
      self.table_name = "#{table_name.singularize}_versions"
      alias_method :readonly?, :persisted?
    end

    private

    def previous_temporal_tsrange_end
      hoardable_source.versions.limit(1).order(hoardable_during: :desc).pluck('hoardable_during').first&.end
    end

    def assign_temporal_tsrange
      self.hoardable_during = ((previous_temporal_tsrange_end || hoardable_source.created_at)..Time.now)
    end
  end
end
