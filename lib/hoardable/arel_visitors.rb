module Hoardable
  # This is a monkey patch of JOIN related {Arel::Visitors} for PostgreSQL so that they can append
  # the ONLY clause when known to be operating on a {Hoardable::Model}. Ideally, {Arel} itself would
  # support this.
  module ArelVisitors
    def visit_Arel_Nodes_FullOuterJoin(o, collector)
      collector << "FULL OUTER JOIN "
      hoardable_maybe_add_only(o, collector)
      collector = visit o.left, collector
      collector << " "
      visit o.right, collector
    end

    def visit_Arel_Nodes_OuterJoin(o, collector)
      collector << "LEFT OUTER JOIN "
      hoardable_maybe_add_only(o, collector)
      collector = visit o.left, collector
      collector << " "
      visit o.right, collector
    end

    def visit_Arel_Nodes_RightOuterJoin(o, collector)
      collector << "RIGHT OUTER JOIN "
      hoardable_maybe_add_only(o, collector)
      collector = visit o.left, collector
      collector << " "
      visit o.right, collector
    end

    def visit_Arel_Nodes_InnerJoin(o, collector)
      collector << "INNER JOIN "
      hoardable_maybe_add_only(o, collector)
      collector = visit o.left, collector
      if o.right
        collector << " "
        visit(o.right, collector)
      else
        collector
      end
    end

    private def hoardable_maybe_add_only(o, collector)
      return unless o.left.instance_variable_get("@klass").in?(Hoardable::REGISTRY)
      return if Hoardable.instance_variable_get("@at")

      collector << "ONLY "
    end
  end
end

Arel::Visitors::PostgreSQL.prepend Hoardable::ArelVisitors
