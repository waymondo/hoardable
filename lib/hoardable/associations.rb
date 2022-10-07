# frozen_string_literal: true

module Hoardable
  # This concern contains +ActiveRecord+ association considerations for {SourceModel}. It is
  # included by {Model} but can be included on it’s own for models that +belongs_to+ a Hoardable
  # {Model}.
  module Associations
    extend ActiveSupport::Concern

    # An +ActiveRecord+ extension that allows looking up {VersionModel}s by +hoardable_source_id+ as
    # if they were {SourceModel}s when using {Hoardable#at}.
    module HasManyExtension
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
    private_constant :HasManyExtension

    class_methods do
      def belongs_to(*args)
        options = args.extract_options!
        trashable = options.delete(:trashable)
        super(*args, **options)
        return unless trashable

        name = args.first
        define_method("trashable_#{name}") do
          source_reflection = self.class.reflections[name.to_s]
          source_reflection.version_class.trashed.only_most_recent.find_by(
            hoardable_source_id: source_reflection.foreign_key
          )
        end

        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            super || trashable_#{name}
          end
        RUBY
      end

      def has_one(*args)
        options = args.extract_options!
        hoardable = options.delete(:hoardable)
        super(*args, **options)
        return unless hoardable

        name = args.first
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            return super unless (at = Hoardable.instance_variable_get('@at'))

            super&.version_at(at) ||
              _reflections["profile"].klass.where(_reflections["profile"].foreign_key => id).first
          end
        RUBY
      end

      def has_many(*args, &block)
        options = args.extract_options!
        options[:extend] = Array(options[:extend]).push(HasManyExtension) if options.delete(:hoardable)
        super(*args, **options, &block)

        name = args.first
        # This hack is needed to force Rails to not use any existing method cache so that the
        # {HasManyExtension} scope is always used.
        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            super.extending
          end
        RUBY
      end
    end
  end
end
