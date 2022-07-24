# frozen_string_literal: true

module Archiversion
  # This concern includes the Archiversion API methods on ActiveRecord instances and dynamically
  # generates the Version variant of the class
  module Model
    extend ActiveSupport::Concern

    class_methods do
      def version_table_name
        "#{table_name.singularize}_versions"
      end

      def version_class_name
        "#{name}Version"
      end
    end

    included do
      default_scope { where("#{table_name}.tableoid = '#{table_name}'::regclass") }
      define_model_callbacks :versioned
      attr_reader :_version

      self_association = model_name.i18n_key
      unless Object.const_defined?(version_class_name)
        version_class = Class.new(self) do
          # TODO: cast to / from ruby class
          # attribute :av_data
          belongs_to self_association, inverse_of: :versions
          self.table_name = version_table_name
          alias_method :readonly?, :persisted?
        end
        Object.const_set(version_class_name, version_class)

        class_eval do
          has_many(:versions, dependent: :destroy, class_name: version_class_name, inverse_of: self_association)
        end
      end
    end

    def versioned_update!(attributes)
      ActiveRecord::Base.transaction do
        @_version = versions.new(dup.attributes)
        run_callbacks :versioned do
          assign_attributes(attributes)
          _version.av_data = { attributes: attributes }
          _version.av_during = (updated_at..Time.now)
          _version.save!
          save!
        end
      end
    end
  end
end
