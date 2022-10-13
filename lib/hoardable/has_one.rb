# frozen_string_literal: true

module Hoardable
  # Provides temporal version awareness to +has_one+ relationships.
  module HasOne
    extend ActiveSupport::Concern

    class_methods do
      def has_one(*args)
        options = args.extract_options!
        hoardable = options.delete(:hoardable)
        association = super(*args, **options)
        name = args.first
        return unless hoardable || association[name.to_s].options[:class_name].match?(/RichText$/)

        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            reflection = _reflections['#{name}']
            return super if reflection.klass.name.match?(/^ActionText/)

            super&.at(hoardable_at_timestamp) ||
              reflection.klass.at(hoardable_at_timestamp).find_by(reflection.foreign_key => hoardable_id)
          end
        RUBY
      end
    end

    included do
      private

      def hoardable_at_timestamp
        Hoardable.instance_variable_get('@at') || updated_at
      rescue NameError
        raise(UpdatedAtColumnMissingError, self.class.table_name)
      end
    end
  end
  private_constant :HasOne
end
