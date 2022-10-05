# frozen_string_literal: true

module Hoardable
  # A module for overriding +ActiveRecord#find_one+’ in the case you are doing a temporal query
  # and the current {SourceModel} record may in fact be a {VersionModel} record.
  module FinderMethods
    def find_one(id)
      super(hoardable_source_ids([id])[0])
    end

    def find_some(ids)
      super(hoardable_source_ids(ids))
    end

    private

    def hoardable_source_ids(ids)
      ids.map do |id|
        version_class.where(hoardable_source_id: id).select(primary_key).ids[0] || id
      end
    end
  end
end
