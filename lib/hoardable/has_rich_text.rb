# frozen_string_literal: true

module Hoardable
  # Provides temporal version awareness for +ActionText+.
  module HasRichText
    extend ActiveSupport::Concern

    class_methods do
      def has_rich_text(name, hoardable: false, **opts)
        super(name, **opts)
        return unless hoardable

        reflection_options = reflections["rich_text_#{name}"].options

        # load the +ActionText+ class if it hasn’t been already
        reflection_options[:class_name].constantize

        reflection_options[:class_name] = reflection_options[:class_name].sub(
          /^ActionText/,
          "Hoardable"
        )
      end

      def has_hoardable_rich_text(name, **opts)
        has_rich_text(name, hoardable: true, **opts)
      end
    end
  end
  private_constant :HasRichText
end
