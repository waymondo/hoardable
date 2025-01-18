module Hoardable
  # Monkey-patches an internal Arel method to ensure that bulk UPDATE's always operates
  # directly on the root table by injecting the ONLY keyword.
  module ArelCrud
    def compile_update(*)
      um = super(*)

      if source.left.instance_variable_get(:@klass).in?(Hoardable::REGISTRY)
        return um.table(Arel.sql("ONLY #{source.left.name}"))
      end

      um
    end
  end
end

Arel::SelectManager.prepend Hoardable::ArelCrud
