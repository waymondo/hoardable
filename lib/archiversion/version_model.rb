# frozen_string_literal: true

module Archiversion
  # This concern is included into the dynamically generated Version models.
  module VersionModel
    extend ActiveSupport::Concern

    included do
      # TODO: cast to / from ruby class
      # attribute :av_data
      belongs_to superclass.model_name.i18n_key, inverse_of: :versions
      self.table_name = "#{table_name.singularize}_versions"
      alias_method :readonly?, :persisted?
    end
  end
end
