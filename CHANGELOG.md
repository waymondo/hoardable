## 0.19.2

- Consult `inheritance_column` when constructing default scope

## 0.19.1

- Thread-safety support added for `with_hoardable_config`.

## 0.19.0

- Ensure that stateful Hoardable class methods `with`, `travel_to` and `at` are thread-safe.

## 0.18.2

- Fix for using `update_all` with Hoardable records.

## 0.18.1

- Support for STI models.

## 0.18.0

- Improved compatibilty with using `ActiveRecord` relationship caching when not using `Hoardable.at`.

## 0.17.0

- Much improved performance of setting `hoardable_id` for versions.

## 0.16.0

- Rails 8 support introduced

## 0.15.0

- *Breaking Change* - Support for Ruby 2.7 and Rails 6.1 is dropped
- *Breaking Change* - The default scoping clause that controls the inherited table SQL construction
  changes from a where clause using `tableoid`s to using `FROM ONLY`
- Fixes an issue for Rails 7.1 regarding accessing version table columns through aliased attributes
- Fixes an issue where `Hoardable::RichText` couldn’t be loaded if `ActionText::RichText` wasn’t yet
  loaded
- Supports dumping `INHERITS (table_name)` options to `schema.rb` and ensures the inherited tables
  are dumped after their parents

## 0.14.3

- The migration template is updated to make the primary key on the versions table its actual primary key

## 0.14.2

- Fixes an eager loading issue regarding `ActionText::EncryptedRichText`

## 0.14.0

- *Breaking Change* - Support for Ruby 2.6 is dropped
- Adjusts the migration and install generators to use the `fx` gem so that Rails 7+ can use `schema.rb`
  instead of `structure.sql`

