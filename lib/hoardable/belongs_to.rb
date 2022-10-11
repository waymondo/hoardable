# frozen_string_literal: true

module Hoardable
  # Provides awareness of trashed source records to +belongs_to+ relationships.
  module BelongsTo
    extend ActiveSupport::Concern

    class_methods do
      def belongs_to(*args)
        options = args.extract_options!
        trashable = options.delete(:trashable)
        super(*args, **options)
        return unless trashable

        hoardable_override_belongs_to(args.first)
      end

      private

      def hoardable_override_belongs_to(name)
        define_method("trashed_#{name}") do
          source_reflection = reflections[name.to_s]
          source_reflection.version_class.trashed.only_most_recent.find_by(
            hoardable_id: source_reflection.foreign_key
          )
        end

        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            super || trashed_#{name}
          end
        RUBY
      end
    end
  end
  private_constant :BelongsTo
end
