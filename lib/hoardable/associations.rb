# frozen_string_literal: true

module Hoardable
  # This concern contains +ActiveRecord+ association considerations for {SourceModel}. It is
  # included by {Model} but can be included on it’s own for models that +belongs_to+ a Hoardable
  # {Model}.
  module Associations
    extend ActiveSupport::Concern

    # An +ActiveRecord+ extension that allows looking up {VersionModel}s by +hoardable_source_id+ as
    # if they were {SourceModel}s when using {Hoardable#at}.
    module Scope
      def scope
        @scope ||= hoardable_scope
      end

      private

      def hoardable_scope
        if Hoardable.instance_variable_get('@at') &&
           (hoardable_source_id = @association.owner.hoardable_source_id)
          @association.scope.rewhere(@association.reflection.foreign_key => hoardable_source_id)
        else
          @association.scope
        end
      end
    end
    private_constant :Scope

    class_methods do
      # A wrapper for +ActiveRecord+’s +belongs_to+ that allows for falling back to the most recent
      # trashed +version+, in the case that the related source has been trashed.
      def belongs_to_trashable(name, scope = nil, **options)
        belongs_to(name, scope, **options)

        trashable_relationship_name = "trashable_#{name}"

        define_method(trashable_relationship_name) do
          source_reflection = self.class.reflections[name.to_s]
          source_reflection.version_class.trashed.only_most_recent.find_by(
            hoardable_source_id: source_reflection.foreign_key
          )
        end

        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            super || #{trashable_relationship_name}
          end
        RUBY
      end

      def has_many(*args, &block)
        options = args.extract_options!
        options[:extend] = Array(options[:extend]).push(Scope) if options.delete(:hoardable)
        super(*args, **options, &block)
      end
    end
  end
end
