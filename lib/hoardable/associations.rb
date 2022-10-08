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

    # A private service class for installing +ActiveRecord+ association overrides.
    class Overrider
      attr_reader :klass

      def initialize(klass)
        @klass = klass
      end

      def override_belongs_to(name)
        klass.define_method("trashed_#{name}") do
          source_reflection = klass.reflections[name.to_s]
          source_reflection.version_class.trashed.only_most_recent.find_by(
            hoardable_source_id: source_reflection.foreign_key
          )
        end

        klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            super || trashed_#{name}
          end
        RUBY
      end

      def override_has_one(name)
        klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            return super unless (at = Hoardable.instance_variable_get('@at'))

            super&.version_at(at) ||
              _reflections['profile'].klass.where(_reflections['profile'].foreign_key => id).first
          end
        RUBY
      end

      def override_has_rich_text(name)
        reflection_options = klass.reflections["rich_text_#{name}"].options
        reflection_options[:class_name] = reflection_options[:class_name].sub(/ActionText/, 'Hoardable')
      end

      def override_has_many(name)
        # This hack is needed to force Rails to not use any existing method cache so that the
        # {HasManyExtension} scope is always used.
        klass.class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            super.extending
          end
        RUBY
      end
    end
    private_constant :Overrider

    class_methods do
      def belongs_to(*args)
        options = args.extract_options!
        trashable = options.delete(:trashable)
        super(*args, **options)
        return unless trashable

        hoardable_association_overrider.override_belongs_to(args.first)
      end

      def has_one(*args)
        options = args.extract_options!
        hoardable = options.delete(:hoardable)
        association = super(*args, **options)
        name = args.first
        return unless hoardable || association[name.to_s].options[:class_name].match?(/RichText$/)

        hoardable_association_overrider.override_has_one(name)
      end

      def has_rich_text(name, encrypted: false, hoardable: false)
        # HACK: to defer loading of ActionText models if they aren’t yet loaded
        'ActionText::RichText'.constantize
        super(name, encrypted: encrypted)
        return unless hoardable

        hoardable_association_overrider.override_has_rich_text(name)
      end

      def has_many(*args, &block)
        options = args.extract_options!
        options[:extend] = Array(options[:extend]).push(HasManyExtension) if options.delete(:hoardable)
        super(*args, **options, &block)

        hoardable_association_overrider.override_has_many(args.first)
      end

      private

      def hoardable_association_overrider
        @hoardable_association_overrider ||= Overrider.new(self)
      end
    end
  end
end
