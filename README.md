# Hoardable ![gem version](https://img.shields.io/gem/v/hoardable?style=flat-square)

Hoardable is an ActiveRecord extension for Ruby 2.6+, Rails 6.1+, and PostgreSQL that allows for
versioning and soft-deletion of records through the use of _uni-temporal inherited tables_.

[👉 Documentation](https://www.rubydoc.info/gems/hoardable)

### huh?

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
be more explicit and obvious on the lower RDBS level while still familiar and convenient within Ruby
on Rails.

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
of that model. As we continue our example above, :

```
$ irb
>> Post
=> Post(id: integer, body: text, user_id: integer, created_at: datetime)
>> PostVersion
=> PostVersion(id: integer, body: text, user_id: integer, created_at: datetime, _data: jsonb, _during: tsrange, post_id: integer)
```

A `Post` now `has_many :versions`. Whenever an update and deletion of a `Post` occurs, a version is
created (by default):

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

If you ever need to revert to a specific version, you can call `version.revert!` on it. If you would
like to untrash a specific version, you can call `version.untrash!` on it. This will re-insert the
model in the parent class’ table with it’s original primary key.

### Querying and Temporal Lookup

Since a `PostVersion` is an `ActiveRecord` class, you can query them like another model resource:

```ruby
post.versions.where(user_id: Current.user.id, body: "Cool!")
```

If you want to look-up the version of a record at a specific time, you can use the `.at` method:

```ruby
post.at(1.day.ago) # => #<PostVersion:0x000000010d44fa30>
# or
PostVersion.at(1.day.ago).find_by(post_id: post.id) # => #<PostVersion:0x000000010d44fa30>
```

By default, `hoardable` will keep copies of records you have destroyed. You can query for them as
well:

```ruby
PostVersion.trashed
```

_Note:_ Creating an inherited table does not copy over the indexes from the parent table. If you
need to query versions often, you should add appropriate indexes to the `_versions` tables.

### Tracking contextual data

You’ll often want to track contextual data about the creation of a version. There are 3 optional
symbol keys that are provided for tracking contextual information:

- `:whodunit` - an identifier for who is responsible for creating the version
- `:note` - a description regarding the versioning
- `:meta` - any other contextual information you’d like to store along with the version

This information is stored in a `jsonb` column. Each key’s value can be in the format of your
choosing.

One convenient way to assign contextual data to these is by defining a proc in an initializer, i.e.:

```ruby
Hoardable.whodunit = -> { Current.user&.id }
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
    # `Hoardable.whodunit` is back to nil or the previously set value
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

There are three configurable options currently:

```ruby
Hoardable.enabled # => default true
Hoardable.version_updates # => default true
Hoardable.save_trash # => default true
```

`Hoardable.enabled` controls whether versions will be ever be created.

`Hoardable.version_updates` controls whether versions get created on record updates.

`Hoardable.save_trash` controls whether to create versions upon record deletion. When this is set to
`false`, all versions of a record will be deleted when the record is destroyed.

If you would like to temporarily set a config setting, you can use `Hoardable.with`:

```ruby
Hoardable.with(enabled: false) do
  post.update!(title: 'unimportant change to create version for')
end
```

You can also configure these variables per `ActiveRecord` class as well using `hoardable_options`:

```ruby
class Comment < ActiveRecord::Base
  include Hoardable::Model
  hoardable_options version_updates: false
end
```

If either the model-level option or global option for a configuration variable is set to `false`,
that behavior will be disabled.

### Relationships

As in life, sometimes relationships can be hard. `hoardable` is still working out best practices and
features in this area, but here are a couple pointers.

Sometimes you’ll have a record that belongs to a record that you’ll trash. Now the child record’s
foreign key will point to the non-existent trashed version of the parent. If you would like this
`belongs_to` relationship to always resolve to the parent as if it was not trashed, you can include
the scope on the relationship definition:

```ruby
belongs_to :parent, -> { include_versions }
```

Sometimes you’ll trash something that `has_many :children, dependent: :destroy` and both the parent
and child model classes include `Hoardable::Model`. Whenever a hoardable version is created in a
database transaction, it will create or re-use a unique event UUID for that transaction and tag all
versions created with it. That way, when you `untrash!` a parent object, you can find and `untrash!`
the children like so:

```ruby
class Post < ActiveRecord::Base
  include Hoardable::Model
  has_many :comments, dependent: :destroy # `Comment` also includes `Hoardable::Model`

  after_untrashed do
    Comment
      .version_class
      .trashed
      .where(post_id: id)
      .with_hoardable_event_uuid(hoardable_event_uuid)
      .find_each(&:untrash!)
  end
end
```

## Contributing

This gem is currently considered alpha and very open to feedback.

Bug reports and pull requests are welcome on GitHub at https://github.com/waymondo/hoardable.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
