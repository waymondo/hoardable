# frozen_string_literal: true

module Hoardable
  # Provides temporal version awareness for +ActionText+.
  module HasRichText
    extend ActiveSupport::Concern

    class_methods do
      def has_rich_text(name, encrypted: false, hoardable: false)
        if SUPPORTS_ENCRYPTED_ACTION_TEXT
          super(name, encrypted: encrypted)
        else
          super(name)
        end
        return unless hoardable

        'ActionText::RichText'.constantize # forces ActionText::RichText to load if it has not
        reflection_options = reflections["rich_text_#{name}"].options
        reflection_options[:class_name] = reflection_options[:class_name].sub(/ActionText/, 'Hoardable')
      end
    end
  end
  private_constant :HasRichText
end
