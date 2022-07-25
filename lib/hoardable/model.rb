# frozen_string_literal: true

module Hoardable
  # This concern includes the Hoardable API methods on ActiveRecord instances and dynamically
  # generates the Version variant of the class
  module Model
    extend ActiveSupport::Concern

    included do
      default_scope { where("#{table_name}.tableoid = '#{table_name}'::regclass") }
      before_update :initialize_version
      before_destroy :initialize_version
      after_update :save_version
      after_destroy :save_version
      attr_reader :hoardable_version

      TracePoint.new(:end) do |trace|
        next unless self == trace.self

        version_class_name = "#{name}Version"
        next if Object.const_defined?(version_class_name)

        Object.const_set(version_class_name, Class.new(self) { include VersionModel })
        class_eval do
          has_many(:versions, dependent: :destroy, class_name: version_class_name, inverse_of: model_name.i18n_key)
        end
        trace.disable
      end.enable
    end

    def at(datetime)
      versions.find_by('hoardable_during @> ?::timestamp', datetime) || self
    end

    private

    def initialize_version
      @hoardable_version = versions.new(
        attributes_before_type_cast.without('id')
          .merge(changes.transform_values { |h| h[0] })
          .merge(hoardable_data: { changes: changes })
      )
    end

    def save_version
      hoardable_version.save!(validate: false, touch: false)
      @hoardable_version = nil
    end
  end
end
