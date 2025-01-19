module Hoardable
  # Monkey-patches an internal Arel method to ensure that bulk UPDATE's always operate
  # directly on the root table by injecting the ONLY keyword.
  module ArelCrud
    def compile_update(*args)
      um = super(*args)

      if source.left.instance_variable_get(:@klass).in?(Hoardable::REGISTRY)
        return um.table(Arel.sql("ONLY #{source.left.name}"))
      end

      um
    end
  end
end

Arel::SelectManager.prepend Hoardable::ArelCrud
