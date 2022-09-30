# frozen_string_literal: true

module Hoardable
  # This concern contains +ActiveRecord+ association considerations for {SourceModel}. It is
  # included by {Model} but can be included on it’s own for models that +belongs_to+ a Hoardable
  # {Model}.
  module Associations
    extend ActiveSupport::Concern

    class_methods do
      # A wrapper for +ActiveRecord+’s +belongs_to+ that allows for falling back to the most recent
      # trashed +version+, in the case that the related source has been trashed.
      def belongs_to_trashable(name, scope = nil, **options)
        belongs_to(name, scope, **options)

        trashable_relationship_name = "trashable_#{name}"

        define_method(trashable_relationship_name) do
          source_reflection = self.class.reflections[name.to_s]
          version_class = source_reflection.klass.version_class
          version_class.trashed.only_most_recent.find_by(
            hoardable_source_id: source_reflection.foreign_key
          )
        end

        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            super || #{trashable_relationship_name}
          end
        RUBY
      end
    end
  end
end
