## 0.15.0

- *Breaking Change* - Support for Ruby 2.7 and Rails 6.1 is dropped
- *Breaking Change* - The default scoping clause that controls the inherited table SQL construction
  changes from a where clause using `tableoid`s to using `FROM ONLY`.

## 0.14.3

- The migration template is updated to make the primary key on the versions table its actual primary key.

## 0.14.2

- Fixes an eager loading issue regarding `ActionText::EncryptedRichText`

## 0.14.0

- *Breaking Change* - Support for Ruby 2.6 is dropped
- Adjusts the migration and install generators to use the `fx` gem so that Rails 7+ can use `schema.rb`
  instead of `structure.sql`

