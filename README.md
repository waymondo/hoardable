# Hoardable

Hoardable is an ActiveRecord extension for Ruby 2.7+, Rails 7+, and PostgreSQL that allows for
versioning and soft-deletion of records through the use of **uni-temporal inherited tables**.

### Huh?

[Temporal tables](https://en.wikipedia.org/wiki/Temporal_database) are a database design pattern
where each row contains data as well as one or more time ranges. In the case of a temporal table
representing versions, each row has one time range representing the row’s valid time range, hence
"uni-temporal".

[Table inheritance](https://www.postgresql.org/docs/14/ddl-inherit.html) is a feature of PostgreSQL
that allows a table to inherit all columns of another table. The descendant table’s schema will stay
in sync with all columns that it inherits from it’s parent. If a new column or removed from the
parent, the schema change is reflected on its descendants.

With these principles combined, `hoardable` offers a simple and effective model versioning system,
where versions of records are stored in a separate, inherited table with the validity time range and
other versioning data.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'hoardable'
```

And then execute `bundle install`.

### Model Installation

First, include `Hoardable::Model` into a model you would like to hoard versions of:

```ruby
class Post < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :user
end
```

Then, run the generator command to create a database migration and migrate it:

```
bin/rails g hoardable:migration posts
bin/rails db:migrate
```

## Usage

### Basics

Once you include `Hoardable::Model` into a model, it will dynamically generate a "Version" subclass
of that model. Continuing our example above:

```
>> Post
=> Post(id: integer, body: text, user_id: integer, created_at: datetime)
>> PostVersion
=> PostVersion(id: integer, body: text, user_id: integer, created_at: datetime, _data: jsonb, _during: tsrange, post_id: integer)
```

A `Post` now `has_many :versions` which are created on every update and deletion of a `Post` (by
default):

```ruby
post_id = post.id
post.versions.size # => 0
post.update!(title: "Title")
post.versions.size # => 1
post.destroy!
post.reload # => ActiveRecord::RecordNotFound
PostVersion.where(post_id: post_id).size # => 2
```

Each `PostVersion` has access to the same attributes, relationships, and other model behavior that
`Post` has, but is a read-only record.

If you ever need to revert to a specific version, you can call `version.revert!` on it. If the
source post had been deleted, this will untrash it with it’s original primary key.

### Querying and Temporal Lookup

Since a `PostVersion` is just a normal `ActiveRecord`, you can query them like another model
resource, i.e:

```ruby
post.versions.where(user_id: Current.user.id, body: nil)
```

If you want to look-up the version of a `Post` at a specific time, you can use the `.at` method:

```ruby
post.at(1.day.ago) # => #<PostVersion:0x000000010d44fa30>
```

By default, `hoardable` will keep copies of records you have destroyed. You can query for them as
well:

```ruby
PostVersion.trashed
```

_Note:_ Creating an inherited table does not copy over the indexes from the parent table. If you
need to query versions often, you will need to add those indexes to the `_versions` tables manually.

### Tracking contextual data

You’ll often want to track contextual data about a version. `hoardable` will automatically capture
the ActiveRecord `changes` hash and `operation` that cause the version (`update` or `delete`).

There are also 3 other optional keys that are provided for tracking contextual information:

- `whodunit` - an identifier for who is responsible for creating the version
- `note` - a string containing a description regarding the versioning
- `meta` - any other contextual information you’d like to store along with the version

This information is stored in a `jsonb` column. Each key’s value can be in the format of your
choosing.

One convenient way to assign this contextual data is with a proc in an initializer, i.e.:

```ruby
Hoardable.whodunit = -> { Current.user&.id }
```

You can also set this context manually as well, just remember to clear them afterwards.

```ruby
Hoardable.note = "reverting due to accidental deletion"
post.update!(title: "We’re back!")
Hoardable.note = nil
post.versions.last.hoardable_note # => "reverting due to accidental deletion"
```

Another useful pattern is to use `Hoardable.with` to set the context around a block. A good example
of this would be in `ApplicationController`:

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

### Model Callbacks

Sometimes you might want to do something with a version before it gets saved. You can access it in a
`before_save` callback as `hoardable_version`. There is also an `after_reverted` callback available
as well.

``` ruby
class User
  before_save :sanitize_version
  after_reverted :track_reverted_event

  private

  def sanitize_version
    hoardable_version.sanitize_password
  end 

  def track_reverted_event
    track_event(:user_reverted, self)
  end
end
```

### Configuration

There are two available options:

``` ruby
Hoardable.enabled # => default true
Hoardable.save_trash # => default true
```

`Hoardable.enabled` controls whether versions will be created at all.

`Hoardable.save_trash` controls whether to create versions upon record deletion. When this is set to
`false`, all versions of a record will be deleted when the record is destroyed.

If you would like to temporarily set a config setting, you can use `Hoardable.with` as well:

```ruby
Hoardable.with(enabled: false) do
  post.update!(title: 'unimportant change to create version for')
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/waymondo/hoardable.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
