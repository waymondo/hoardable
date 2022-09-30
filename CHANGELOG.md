## [Unreleased]

- Stability is coming.

## [0.7.0] - 2022-09-29

- **Breaking Change** - Continuing along with the change below, the `foreign_key` for this
  relationship has now changed to `hoardable_source_id` for all `_versions` tables. The intent is to
  never leave room for confliction of foreign keys for existing relationships. This can be resolved
  by renaming the columns from their i18n model name derived column names to `hoardable_source_id`.

## [0.6.0] - 2022-09-28

- **Breaking Change** - Previously, a source model would `has_many :versions` with an inverse
  relationship based on the i18n interpreted name of the source model. Now it simply `has_many
  :versions, inverse_of :hoardable_source` to not potentially conflict with previously existing
  relationships.

## [0.5.0] - 2022-09-25

- **Breaking Change** - Untrashing a version will now insert a version for the untrash event with
  it's own temporal timespan. This simplifies the ability to query versions temporarily for when
  they were trashed or not. This changes, but corrects, temporal query results using `.at`.

- **Breaking Change** - Because of the above, a new operation enum value of "insert" was added. If
  you already have the `hoardable_operation` enum in your PostgreSQL schema, you can add it by
  executing the following SQL in a new migration: `ALTER TYPE hoardable_operation ADD VALUE
  'insert';`.

## [0.4.0] - 2022-09-24

- **Breaking Change** - Trashed versions now pull from the same postgres sequenced used by the
  source model’s table.

## [0.1.0] - 2022-07-23

- Initial release
