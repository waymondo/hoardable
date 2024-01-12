# Hoardable ![gem version](https://img.shields.io/gem/v/hoardable?style=flat-square)

Hoardable is an ActiveRecord extension for Ruby 3+, Rails 7+, and PostgreSQL 9+ that allows for
versioning and soft-deletion of records through the use of _uni-temporal inherited tables_.

[Temporal tables](https://en.wikipedia.org/wiki/Temporal_database) are a database design pattern
where each row of a table contains data along with one or more time ranges. In the case of this gem,
each database row has a time range that represents the row’s valid time range - hence
"uni-temporal".

[Table inheritance](https://www.postgresql.org/docs/current/ddl-inherit.html) is a feature of
PostgreSQL that allows one table to inherit all columns from a parent. The descendant table’s schema
will stay in sync with its parent; if a new column is added to or removed from the parent, the
schema change is reflected on its descendants.

With these concepts combined, `hoardable` offers a model versioning and soft deletion system for
Rails. Versions of records are stored in separate, inherited tables along with their valid time
ranges and contextual data.

[👉 Documentation](https://www.rubydoc.info/gems/hoardable)

## Installation

Add this line to your application's Gemfile:

```ruby
gem "hoardable"
```

Run `bundle install`, and then run:

```
bin/rails g hoardable:install
bin/rails db:migrate
```

### Model installation

Include `Hoardable::Model` into an ActiveRecord model you would like to hoard versions of:

```ruby
class Post < ActiveRecord::Base
  include Hoardable::Model
  ...
end
```

Run the generator command to create a database migration and migrate it:

```
bin/rails g hoardable:migration Post
bin/rails db:migrate
```

_*Note*:_ Creating an inherited table does not inherit the indexes from the parent table. If you
need to query versions often, you should add appropriate indexes to the `_versions` tables.

## Usage

### Overview

Once you include `Hoardable::Model` into a model, it will dynamically generate a "Version" subclass
of that model. As we continue our example from above:

```ruby
Post #=> Post(id: integer, ..., hoardable_id: integer)
PostVersion #=> PostVersion(id: integer, ..., hoardable_id: integer, _data: jsonb, _during: tsrange, _event_uuid: uuid, _operation: enum)
Post.version_class #=> same as `PostVersion`
```

A `Post` now `has_many :versions`. With the default configuration, whenever an update or deletion of
a `post` occurs, a version is created:

```ruby
post = Post.create!(title: "Title")
post.versions.size # => 0
post.update!(title: "Revised Title")
post.reload.versions.size # => 1
post.versions.first.title # => "Title"
post.destroy!
post.trashed? # true
post.versions.size # => 2
Post.find(post.id) # raises ActiveRecord::RecordNotFound
```

Each `PostVersion` has access to the same attributes, relationships, and other model behavior that
`Post` has, but as a read-only record:

```ruby
post.versions.last.update!(title: "Rewrite history") #=> raises ActiveRecord::ReadOnlyRecord
```

If you ever need to revert to a specific version, you can call `version.revert!` on it.

```ruby
post = Post.create!(title: "Title")
post.update!(title: "Whoops")
version = post.reload.versions.last
version.title # -> "Title"
version.revert!
post.title # => "Title"
```

If you would like to untrash a specific version of a record you deleted, you can call
`version.untrash!` on it. This will re-insert the model in the parent class’s table with the
original primary key.

```ruby
post = Post.create!(title: "Title")
post.destroy!
post.versions.size # => 1
Post.find(post.id) # raises ActiveRecord::RecordNotFound
trashed_post = post.versions.trashed.last
trashed_post.untrash!
Post.find(post.id) # #<Post>
```

Source and version records pull from the same ID sequence. This allows for uniquely identifying
records from each other. Both source record and version have an automatically managed `hoardable_id`
attribute that always represents the primary key value of the original source record:

```ruby
post = Post.create!(title: "Title")
post.id # => 1
post.hoardable_id # => 1
post.version? # => false
post.update!(title: "New Title")
version = post.reload.versions.last
version.id # => 2
version.hoardable_id # => 1
version.version? # => true
```

### Querying and temporal lookup

Including `Hoardable::Model` into your source model modifies `default_scope` to make sure you only
ever query the parent table and not the inherited ones:

```ruby
Post.where(state: :draft).to_sql # => SELECT posts.* FROM ONLY posts WHERE posts.status = 'draft'
```

Note the `FROM ONLY` above. If you are executing raw SQL, you will need to include the `ONLY`
keyword if you do not wish to return versions in your results. This includes `JOIN`-ing on this
table as well.

```ruby
User.joins(:posts).to_sql # => SELECT users.* FROM users INNER JOIN ONLY posts ON posts.user_id = users.id
```

Learn more about table inheritance in [the PostgreSQL documentation](https://www.postgresql.org/docs/current/ddl-inherit.html).

Since a `PostVersion` is an `ActiveRecord` class, you can query them like another model resource:

```ruby
post.versions.where(state: :draft)
```

By default, `hoardable` will keep copies of records you have destroyed. You can query them
specifically with:

```ruby
PostVersion.trashed.where(user_id: user.id)
Post.version_class.trashed.where(user_id: user.id) # <- same as above
```

If you want to look-up the version of a record at a specific time, you can use the `.at` method:

```ruby
post.at(1.day.ago) # => #<PostVersion>
# or you can use the scope on the version model class
post.versions.at(1.day.ago) # => #<PostVersion>
PostVersion.at(1.day.ago).find_by(hoardable_id: post.id) # => same as above
```

The source model class also has an `.at` method:

```ruby
Post.at(1.day.ago) # => [#<Post>, #<Post>]
```

This will return an ActiveRecord scoped query of all `Post` and `PostVersion` records that were
valid at that time, all cast as instances of `Post`. Updates to the versions table are forbidden in
this case by a database trigger.

There is also `Hoardable.at` for more complex and experimental temporal resource querying. See
[Relationships](#relationships) for more.

### Tracking contextual data

You’ll often want to track contextual data about the creation of a version. There are 2 options that
can be provided for tracking this:

- `:whodunit` - an identifier for who/what is responsible for creating the version
- `:meta` - any other contextual information you’d like to store along with the version

This information is stored in a `jsonb` column. Each value can be the data type of your choosing.

One convenient way to assign contextual data to these is by defining a proc in an initializer, i.e.:

```ruby
# config/initializers/hoardable.rb
Hoardable.whodunit = -> { Current.user&.id }

# somewhere in your app code
Current.set(user: User.find(123)) do
  post.update!(status: :live)
  post.reload.versions.last.hoardable_whodunit # => 123
end
```

Another useful pattern would be to use `Hoardable.with` to set the context around a block. For
example, you could have the following in your `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  around_action :use_hoardable_context

  private

  def use_hoardable_context
    Hoardable.with(whodunit: current_user.id, meta: { request_uuid: request.uuid }) do
      yield
    end
  end
end
```

[ActiveRecord changes](https://api.rubyonrails.org/classes/ActiveModel/Dirty.html#method-i-changes)
are also automatically captured along with the `operation` that caused the version (`update` or
`delete`). These values are available as:

```ruby
version.changes # => { "title"=> ["Title", "New Title"] }
version.hoardable_operation # => "update"
```

### Model Callbacks

Sometimes you might want to do something with a version after it gets inserted to the database. You
can access it in `after_versioned` callbacks on the source record as `hoardable_version`. These
happen within `ActiveRecord#save`'s transaction.

There are also `after_reverted` and `after_untrashed` callbacks available as well, which are called
on the source record after a version is reverted or untrashed.

```ruby
class User
  include Hoardable::Model
  after_versioned :track_versioned_event
  after_reverted :track_reverted_event
  after_untrashed :track_untrashed_event

  private

  def track_versioned_event
    track_event(:user_versioned, hoardable_version)
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
Hoardable.enabled # => true
Hoardable.version_updates # => true
Hoardable.save_trash # => true
```

`Hoardable.enabled` globally controls whether versions will be ever be created.

`Hoardable.version_updates` globally controls whether versions get created on record updates.

`Hoardable.save_trash` globally controls whether to create versions upon source record deletion.
When this is set to `false`, all versions of a source record will be deleted when the record is
destroyed.

If you would like to temporarily set a config value, you can use `Hoardable.with`:

```ruby
Hoardable.with(enabled: false) do
  post.update!(title: "replace title without creating a version")
end
```

You can also configure these settings per `ActiveRecord` class using `hoardable_config`:

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

Model-level configuration overrides global configuration.

## Relationships

### `belongs_to`

Sometimes you’ll have a record that belongs to a parent record that you’ll trash. Now the child
record’s foreign key will point to the non-existent trashed version of the parent. If you would like
to have `belongs_to` resolve to the trashed parent model in this case, you can give it the option of
`trashable: true`:

```ruby
class Post
  include Hoardable::Model
  has_many :comments, dependent: nil
end

class Comment
  include Hoardable::Associations # <- This includes is not required if this model already includes `Hoardable::Model`
  belongs_to :post, trashable: true
end

post = Post.create!(title: "Title")
comment = post.comments.create!(body: "Comment")
post.destroy!
comment.post # => #<PostVersion>
```

### `has_many` & `has_one`

Sometimes you'll have a Hoardable record that `has_one` or `has_many` other Hoardable records and
you’ll want to know the state of both the parent record and the children at a certain point in time.
You can accomplish this by adding `hoardable: true` to the `has_many` relationship and using the
`Hoardable.at` method:

```ruby
class Post
  include Hoardable::Model
  has_many :comments, hoardable: true
end

class Comment
  include Hoardable::Model
end

post = Post.create!(title: "Title")
comment1 = post.comments.create!(body: "Comment")
comment2 = post.comments.create!(body: "Comment")
datetime = DateTime.current

comment2.destroy!
post.update!(title: "New Title")
post_id = post.id # 1

Hoardable.at(datetime) do
  post = Post.find(post_id)
  post.title # => "Title"
  post.comments.size # => 2
  post.version? # => true
  post.id # => 2
  post.hoardable_id # => 1
end
```

_*Note*:_ `Hoardable.at` is experimental and potentially not performant for querying very large data
sets.

### Cascading Untrashing

Sometimes you’ll trash something that `has_many :children, dependent: :destroy` and if you untrash
the parent record, you’ll want to also untrash the children. Whenever a hoardable versions are
created, it will share a unique event UUID for all other versions created in the same database
transaction. That way, when you `untrash!` a record, you could find and `untrash!` records that were
trashed with it:

```ruby
class Comment < ActiveRecord::Base
  include Hoardable::Model
end

class Post < ActiveRecord::Base
  include Hoardable::Model
  has_many :comments, hoardable: true, dependent: :destroy

  after_untrashed do
    Comment
      .version_class
      .trashed
      .with_hoardable_event_uuid(hoardable_event_uuid)
      .find_each(&:untrash!)
  end
end
```

### Action Text

Hoardable provides support for ActiveRecord models with `has_rich_text`. First, you must create a
temporal table for `ActionText::RichText`:

```
bin/rails g hoardable:migration ActionText::RichText
bin/rails db:migrate
```

Then in your model include `Hoardable::Model` and provide the `hoardable: true` keyword to
`has_rich_text`:

```ruby
class Post < ActiveRecord::Base
  include Hoardable::Model # or `Hoardable::Associations` if you don't need `PostVersion`
  has_rich_text :content, hoardable: true # or `has_hoardable_rich_text :content`
end
```

Now the `rich_text_content` relationship will be managed as a Hoardable `has_one` relationship:

```ruby
post = Post.create!(content: '<div>Hello World</div>')
datetime = DateTime.current
post.update!(content: '<div>Goodbye Cruel World</div>')
post.content.versions.size # => 1
post.content.to_plain_text # => 'Goodbye Cruel World'
Hoardable.at(datetime) do
  post.content.to_plain_text # => 'Hello World'
end
```

## Known gotchas

### Rails fixtures

Rails uses a method called
[`disable_referential_integrity`](https://github.com/rails/rails/blob/06e9fbd954ab113108a7982357553fdef285bff1/activerecord/lib/active_record/connection_adapters/postgresql/referential_integrity.rb#L7)
when inserting fixtures into the database. This disables PostgreSQL triggers, which Hoardable relies
on for assigning `hoardable_id` from the primary key’s value. If you would still like to use
fixtures, you must specify the primary key’s value and `hoardable_id` to the same identifier value
in the fixture.

## Gem comparison

#### [`paper_trail`](https://github.com/paper-trail-gem/paper_trail)

`paper_trail` is maybe the most popular and fully featured gem in this space. It works for other
database types than PostgeSQL. Bby default it stores all versions of all versioned models in a
single `versions` table. It stores changes in a `text`, `json`, or `jsonb` column. In order to
efficiently query the `versions` table, a `jsonb` column should be used, which can take up a lot of
space to index. Unless you customize your configuration, all `versions` for all models types are in
the same table which is inefficient if you are only interested in querying versions of a single
model. By contrast, `hoardable` stores versions in smaller, isolated, inherited tables with the same
database columns as their parents, which are more efficient for querying as well as auditing for
truncating and dropping. The concept of a temporal timeframe does not exist for a single version
since there is only a `created_at` timestamp.

#### [`audited`](https://github.com/collectiveidea/audited)

`audited` works in a similar manner as `paper_trail`. It stores all versions for all model types in
a single table, you must opt into using `jsonb` as the column type to store "changes", in case you
want to query them, and there is no concept of a temporal timeframe for a single version. It makes
opinionated decisions about contextual data requirements and stores them as top level data types on
the `audited` table.

#### [`discard`](https://github.com/jhawthorn/discard)

`discard` only covers soft-deletion. The act of "soft deleting" a record is only captured through
the time-stamping of a `discarded_at` column on the records table. There is no other capturing of
the event that caused the soft deletion unless you implement it yourself. Once the "discarded"
record is restored, the previous "discarded" awareness is lost. Since "discarded" records exist in
the same table as "undiscarded" records, you must explicitly omit the discarded records from queries
across your app to keep them from leaking in.

#### [`paranoia`](https://github.com/rubysherpas/paranoia)

`paranoia` also only covers soft-deletion. In their README, they recommend using `discard` instead
of `paranoia` because of the fact they override ActiveRecord’s `delete` and `destroy` methods.
`hoardable` employs callbacks to create trashed versions instead of overriding methods. Otherwise,
`paranoia` works similarly to `discard` in that it keeps deleted records in the same table and tags
them with a `deleted_at` timestamp. No other information about the soft-deletion event is stored.

#### [`logidze`](https://github.com/palkan/logidze)

`logidze` is an interesting versioning alternative that leverages the power of PostgreSQL triggers.
Instead of storing the previous versions or changes in a separate table, it stores them in a
proprietary JSON format directly on the database row of the record itself. If does not support soft
deletion.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/waymondo/hoardable.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
