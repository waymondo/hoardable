## [Unreleased]

- Stability is coming.

## [0.10.0] - 2022-10-06

- `has_many_hoardable` was replaced with `has_many :resources, hoardable: true`.

- **Breaking Change** - a `created_at` column is now required for `Hoardable::Model`s.

## [0.9.0] - 2022-10-02

- **Breaking Change** - `Hoardable.return_everything` was removed in favor of the newly added
  `Hoardable.at`.

## [0.8.0] - 2022-10-01

- **Breaking Change** - Due to the performance benefit of using `insert` for database injection of
  versions, and a personal opinion that only an `after_versioned` hook might be needed, the
  `before_versioned` and `around_versioned` ActiveRecord hooks are removed.

- **Breaking Change** - Another side effect of the performance benefit gained by using `insert` is
  that a source model will need to be reloaded before a call to `versions` on it can access the
  latest version after an `update` on the source record.

- **Breaking Change** - Previously the inherited `_versions` tables did not have a unique index on
  the ID column, though it still pulled from the same sequence as the parent table. Prior to version
  0.4.0 though, it was possible to have multiple trashed versions with the same ID. Adding unique
  indexes to version tables prior to version 0.4.0 could result in issues.

## [0.7.0] - 2022-09-29

- **Breaking Change** - Continuing along with the change below, the `foreign_key` on the `_versions`
  tables is now changed to `hoardable_source_id` instead of the i18n model name dervied foreign key.
  The intent is to never leave room for conflict of foreign keys for existing relationships. This
  can be resolved by renaming the foreign key columns from their i18n model name derived column
  names to `hoardable_source_id`, i.e. `rename_column :post_versions, :post_id, :hoardable_source_id`.

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
