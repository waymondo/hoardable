# frozen_string_literal: true

module Hoardable
  # Provides temporal version awareness for +ActionText+.
  module HasRichText
    extend ActiveSupport::Concern

    class_methods do
      def has_rich_text(name, encrypted: false, hoardable: false)
        # HACK: to load deferred ActionText models if they aren’t yet loaded
        'ActionText::RichText'.constantize
        super(name, encrypted: encrypted)
        return unless hoardable

        reflection_options = reflections["rich_text_#{name}"].options
        reflection_options[:class_name] = reflection_options[:class_name].sub(/ActionText/, 'Hoardable')
      end
    end
  end
  private_constant :HasRichText
end
