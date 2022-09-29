# Hoardable ![gem version](https://img.shields.io/gem/v/hoardable?style=flat-square)

Hoardable is an ActiveRecord extension for Ruby 2.6+, Rails 6.1+, and PostgreSQL that allows for
versioning and soft-deletion of records through the use of _uni-temporal inherited tables_.

[Temporal tables](https://en.wikipedia.org/wiki/Temporal_database) are a database design pattern
where each row of a table contains data along with one or more time ranges. In the case of this gem,
each database row has a time range that represents the row’s valid time range - hence
"uni-temporal".

[Table inheritance](https://www.postgresql.org/docs/14/ddl-inherit.html) is a feature of PostgreSQL
that allows a table to inherit all columns of a parent table. The descendant table’s schema will
stay in sync with its parent. If a new column is added to or removed from the parent, the schema
change is reflected on its descendants.

With these concepts combined, `hoardable` offers a simple and effective model versioning system for
Rails. Versions of records are stored in separate, inherited tables along with their valid time
ranges and contextual data. Compared to other Rails-oriented versioning systems, this gem strives to
be more explicit and obvious on the lower RDBS level while still familiar and convenient to use
within Ruby on Rails.

[👉 Documentation](https://www.rubydoc.info/gems/hoardable)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hoardable'
```

And then execute `bundle install`.

### Model Installation

You must include `Hoardable::Model` into an ActiveRecord model that you would like to hoard versions
of:

```ruby
class Post < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :user
  has_many :comments, dependent: :destroy
  ...
end
```

Then, run the generator command to create a database migration and migrate it:

```
bin/rails g hoardable:migration Post
bin/rails db:migrate
```

By default, it will try to guess the foreign key type for the `_versions` table based on the primary
key of the model specified in the migration generator above. If you want/need to specify this
explicitly, you can do so:

```
bin/rails g hoardable:migration Post --foreign-key-type uuid
```

_Note:_ If you are on Rails 6.1, you might want to set `config.active_record.schema_format = :sql`
in `application.rb`, so that the enum type is captured in your schema dump. This is not required in
Rails 7.

## Usage

### Overview

Once you include `Hoardable::Model` into a model, it will dynamically generate a "Version" subclass
of that model. As we continue our example from above:

```
$ irb
>> Post
=> Post(id: integer, body: text, user_id: integer, created_at: datetime)
>> PostVersion
=> PostVersion(id: integer, body: text, user_id: integer, created_at: datetime, _data: jsonb, _during: tsrange, post_id: integer)
```

A `Post` now `has_many :versions`. With the default configuration, whenever an update and deletion
of a `Post` occurs, a version is created:

```ruby
post = Post.create!(title: "Title")
post.versions.size # => 0
post.update!(title: "Revised Title")
post.versions.size # => 1
post.versions.first.title # => "Title"
post.destroy!
post.trashed? # true
post.versions.size # => 2
Post.find(post.id) # raises ActiveRecord::RecordNotFound
```

Each `PostVersion` has access to the same attributes, relationships, and other model behavior that
`Post` has, but as a read-only record.

If you ever need to revert to a specific version, you can call `version.revert!` on it.

``` ruby
post = Post.create!(title: "Title")
post.update!(title: "Whoops")
post.versions.last.revert!
post.title # => "Title"
```

If you would like to untrash a specific version, you can call `version.untrash!` on it. This will
re-insert the model in the parent class’s table with it’s original primary key.

```ruby
post = Post.create!(title: "Title")
post.id # => 1
post.destroy!
post.versions.size # => 1
Post.find(post.id) # raises ActiveRecord::RecordNotFound
trashed_post = post.versions.trashed.last
trashed_post.id # => 2
trashed_post.untrash!
Post.find(post.id) # #<Post>
```

### Querying and Temporal Lookup

Since a `PostVersion` is an `ActiveRecord` class, you can query them like another model resource:

```ruby
post.versions.where(user_id: Current.user.id, body: "Cool!")
```

If you want to look-up the version of a record at a specific time, you can use the `.at` method:

```ruby
post.at(1.day.ago) # => #<PostVersion>
# or you can use the scope on the version model class
PostVersion.at(1.day.ago).find_by(post_id: post.id) # => #<PostVersion>
```

The source model class also has an `.at` method:

``` ruby
Post.at(1.day.ago) # => [#<Post>, #<Post>]
```

This will return an ActiveRecord scoped query of all `Posts` and `PostVersions` that were valid at
that time, all cast as instances of `Post`.

_Note:_ A `Version` is not created upon initial parent model creation. To accurately track the
beginning of the first temporal period, you will need to ensure the source model table has a
`created_at` timestamp column.

By default, `hoardable` will keep copies of records you have destroyed. You can query them
specifically with:

```ruby
PostVersion.trashed
Post.version_class.trashed # <- same thing as above
```

_Note:_ Creating an inherited table does not copy over the indexes from the parent table. If you
need to query versions often, you should add appropriate indexes to the `_versions` tables.

### Tracking Contextual Data

You’ll often want to track contextual data about the creation of a version. There are 3 optional
symbol keys that are provided for tracking contextual information:

- `:whodunit` - an identifier for who is responsible for creating the version
- `:note` - a description regarding the versioning
- `:meta` - any other contextual information you’d like to store along with the version

This information is stored in a `jsonb` column. Each key’s value can be in the format of your
choosing.

One convenient way to assign contextual data to these is by defining a proc in an initializer, i.e.:

```ruby
# config/initializers/hoardable.rb
Hoardable.whodunit = -> { Current.user&.id }

# somewhere in your app code
Current.user = User.find(123)
post.update!(status: 'live')
post.versions.last.hoardable_whodunit # => 123
```

You can also set this context manually as well, just remember to clear them afterwards.

```ruby
Hoardable.note = "reverting due to accidental deletion"
post.update!(title: "We’re back!")
Hoardable.note = nil
post.versions.last.hoardable_note # => "reverting due to accidental deletion"
```

A more useful pattern is to use `Hoardable.with` to set the context around a block. A good example
of this would be in `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  around_action :use_hoardable_context

  private

  def use_hoardable_context
    Hoardable.with(whodunit: current_user.id, meta: { request_uuid: request.uuid }) do
      yield
    end
    # `Hoardable.whodunit` and `Hoardable.meta` are back to nil or their previously set values
  end
end
```

`hoardable` will also automatically capture the ActiveRecord
[changes](https://api.rubyonrails.org/classes/ActiveModel/Dirty.html#method-i-changes) hash, the
`operation` that cause the version (`update` or `delete`), and it will also tag all versions created
in the same database transaction with a shared and unique `event_uuid`. These are available as:

```ruby
version.changes
version.hoardable_operation
version.hoardable_event_uuid
```

### Model Callbacks

Sometimes you might want to do something with a version before or after it gets inserted to the
database. You can access it in `before/after/around_versioned` callbacks on the source record as
`hoardable_version`. These happen around `.save`, which is enclosed in an ActiveRecord transaction.

There are also `after_reverted` and `after_untrashed` callbacks available as well, which are called
on the source record after a version is reverted or untrashed.

```ruby
class User
  include Hoardable::Model
  before_versioned :sanitize_version
  after_reverted :track_reverted_event
  after_untrashed :track_untrashed_event

  private

  def sanitize_version
    hoardable_version.sanitize_password
  end

  def track_reverted_event
    track_event(:user_reverted, self)
  end

  def track_untrashed_event
    track_event(:user_untrashed, self)
  end
end
```

### Configuration

The configurable options are:

```ruby
Hoardable.enabled # => default true
Hoardable.version_updates # => default true
Hoardable.save_trash # => default true
Hoardable.return_everything # => default false
```

`Hoardable.enabled` controls whether versions will be ever be created.

`Hoardable.version_updates` controls whether versions get created on record updates.

`Hoardable.save_trash` controls whether to create versions upon record deletion. When this is set to
`false`, all versions of a record will be deleted when the record is destroyed.

`Hoardable.return_everything` controls whether to include versions when doing queries for source
models. This is typically only useful to set around a block, as explained below in
[Relationships](#relationships).

If you would like to temporarily set a config setting, you can use `Hoardable.with`:

```ruby
Hoardable.with(enabled: false) do
  post.update!(title: 'unimportant change to create version for')
end
```

You can also configure these variables per `ActiveRecord` class as well using `hoardable_config`:

```ruby
class Comment < ActiveRecord::Base
  include Hoardable::Model
  hoardable_config version_updates: false
end
```

If you want to temporarily set the `hoardable_config` for a specific model, you can use
`with_hoardable_config`:

```ruby
Comment.with_hoardable_config(version_updates: true) do
  comment.update!(text: "Edited")
end
```

If a model-level option exists, it will use that. Otherwise, it will fall back to the global
`Hoardable` config.

### Relationships

As in life, sometimes relationships can be hard, but here are some pointers on handling associations
with `Hoardable` considerations.

Sometimes you’ll have a record that belongs to a parent record that you’ll trash. Now the child
record’s foreign key will point to the non-existent trashed version of the parent. If you would like
to have `belongs_to` resolve to the trashed parent model in this case, you can use
`belongs_to_trashable` in place of `belongs_to`:

```ruby
class Comment
  include Hoardable::Associations # <- This includes is not required if this model already includes `Hoardable::Model`
  belongs_to_trashable :post, -> { where(status: 'published') }, class_name: 'Article' # <- Accepts normal `belongs_to` arguments
end
```

Sometimes you’ll trash something that `has_many :children, dependent: :destroy` and both the parent
and child model classes include `Hoardable::Model`. Whenever a hoardable version is created in a
database transaction, it will create or re-use a unique event UUID for that transaction and tag all
versions created with it. That way, when you `untrash!` a record, you can find and `untrash!`
records that were trashed with it:

```ruby
class Post < ActiveRecord::Base
  include Hoardable::Model
  has_many :comments, dependent: :destroy # `Comment` also includes `Hoardable::Model`

  after_untrashed do
    Comment
      .version_class
      .trashed
      .with_hoardable_event_uuid(hoardable_event_uuid)
      .find_each(&:untrash!)
  end
end
```

If there are models that might be related to versions that are trashed or otherwise, and/or might be
trashed themselves, you can bypass the inherited tables query handling altogether by using the
`return_everything` configuration variable in `Hoardable.with`. This will ensure that you always see
all records, including update and trashed versions.

```ruby
post.destroy!

Hoardable.with(return_everything: true) do
  post = Post.find(post.id) # returns the trashed post as if it was not
  post.comments # returns the trashed comments as well
end

post.reload # raises ActiveRecord::RecordNotFound
```

## Gem Comparison

### [`paper_trail`](https://github.com/paper-trail-gem/paper_trail)

`paper_trail` is maybe the most popular and fully featured gem in this space. It works for other
database types than PostgeSQL and (by default) stores all versions of all versioned models in a
single `versions` table. It stores changes in a `text`, `json`, or `jsonb` column. In order to
efficiently query the `versions` table, a `jsonb` column should be used, which takes up a lot of
space to index. Unless you customize your configuration, all `versions` for all models types are
in the same table which is inefficient if you are only interested in querying versions of a single
model. By contrast, `hoardable` stores versions in smaller, isolated and inherited tables with the
same database columns as their parents, which are more efficient for querying as well as auditing
for truncating and dropping. The concept of a `temporal` time-frame does not exist for a single
version since there is only a `created_at` timestamp.

### [`audited`](https://github.com/collectiveidea/audited)

`audited` works in a similar manner as `paper_trail`. It stores all versions for all model types in
a single table, you must opt into using `jsonb` as the column type to store "changes", in case you
want to query them, and there is no concept of a `temporal` time-frame for a single version. It
makes opinionated decisions about contextual data requirements and stores them as top level data
types on the `audited` table.

### [`discard`](https://github.com/jhawthorn/discard)

`discard` only covers soft-deletion. The act of "soft deleting" a record is only captured through
the time-stamping of a `discarded_at` column on the records table; there is no other capturing of
the event that caused the soft deletion unless you implement it yourself. Once the "discarded"
record is restored, the previous "discarded" awareness is lost. Since "discarded" records exist in
the same table as "undiscarded" records, you must explicitly omit the discarded records from queries
across your app to keep them from leaking in.

### [`paranoia`](https://github.com/rubysherpas/paranoia)

`paranoia` also only covers soft-deletion. In their README, they recommend using `discard` instead
of `paranoia` because of the fact they override ActiveRecord’s `delete` and `destroy` methods.
`hoardable` employs callbacks to create trashed versions instead of overriding methods. Otherwise,
`paranoia` works similarly to `discard` in that it keeps deleted records in the same table and tags
them with a `deleted_at` timestamp. No other information about the soft-deletion event is stored.

## Contributing

This gem still quite new and very open to feedback.

Bug reports and pull requests are welcome on GitHub at https://github.com/waymondo/hoardable.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
