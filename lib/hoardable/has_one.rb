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
            return super unless (at = Hoardable.instance_variable_get('@at'))

            super&.version_at(at) ||
              _reflections['profile'].klass.where(_reflections['profile'].foreign_key => id).first
          end
        RUBY
      end
    end
  end
  private_constant :HasOne
end
