# frozen_string_literal: true

module Hoardable
  # Provides temporal version awareness to +has_one+ relationships.
  module HasOne
    extend ActiveSupport::Concern

    class_methods do
      def has_one(*args)
        options = args.extract_options!
        hoardable = options.delete(:hoardable)
        name = args.first
        association = super(*args, **options).symbolize_keys[name]
        return unless hoardable || (association.options[:class_name].match?(/RichText$/))

        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            reflection = _reflections.symbolize_keys[:#{name}]
            return super if reflection.klass.name.match?(/^ActionText/)
            return super unless (timestamp = hoardable_client.has_one_at_timestamp)

            super&.at(timestamp) ||
              reflection.klass.at(timestamp).find_by(hoardable_client.has_one_find_conditions(reflection))
          end
        RUBY
      end
    end
  end
  private_constant :HasOne
end
