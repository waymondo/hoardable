# frozen_string_literal: true

module Hoardable
  # A module for overriding +ActiveRecord#find_one+ and +ActiveRecord#find_some+ in the case you are
  # doing a temporal query and the current {SourceModel} record may in fact be a {VersionModel}
  # record. This is extended into the current scope with {Hoardable#at} but can also be opt-ed into
  # with the class method +hoardable+.
  module FinderMethods
    def find_one(id)
      super(hoardable_ids([id])[0])
    end

    def find_some(ids)
      super(hoardable_ids(ids))
    end

    private

    def hoardable_ids(ids)
      ids.map { |id| version_class.where(hoardable_id: id).select(primary_key).ids[0] || id }
    end
  end
end
