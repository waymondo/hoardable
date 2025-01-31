# frozen_string_literal: true

require "helper"

class TestModel < ActiveSupport::TestCase
  setup { reset_db }

  private def user
    @user ||= User.create!(name: "Justin")
  end

  private def post
    @post ||= Post.create!(title: "Headline", user: user)
  end

  private def update_post(attributes = { title: "New Headline", status: :live })
    post.update!(attributes)
    assert_equal post.status.to_sym, attributes[:status]
    assert_equal post.title, attributes[:title]
  end

  test "can do the very first readme example" do
    assert_equal post.versions.size, 0
    update_post
    assert_equal post.reload.versions.size, 1
    post.destroy!
    assert post.trashed?
    assert_equal post.versions.size, 2
    assert_raises(ActiveRecord::RecordNotFound) { Post.find(post.id) }
  end

  test "creates a version with previous state and generated columns" do
    assert_equal post.versions.size, 0
    update_post
    assert_equal post.reload.versions.size, 1
    version = post.versions.first
    assert_equal version.status, "draft"
    assert_equal version.title, "Headline"
    assert_equal version.lowercase_title, "headline"
  end

  test "uses current db version and not the current ruby attribute value for version" do
    post.title = "Draft Headline"
    update_post
    assert_equal post.versions.size, 1
    version = post.versions.first
    assert_equal version.title, "Headline"
  end

  test "creates read-only versions that do not themselves have versions" do
    update_post
    version = post.versions.first
    assert_raises(ActiveRecord::ReadOnlyRecord) { version.update!(title: "Rewriting History") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { version.destroy! }
    assert_raises(ActiveRecord::AssociationNotFoundError) { version.versions }
  end

  test "preserves created_at timestamps, expects during tsrange is set" do
    update_post
    version = post.versions.first
    assert_equal post.created_at, version.created_at
    assert version._during
  end

  test "knows how to dynamically create namespaced version classes" do
    post = Hoardable::Post.create!(title: "Hi", user: user)
    post.update!(title: "Bye")
    assert_instance_of Hoardable::PostVersion, post.versions.first
  end

  test "works with serialized attributes" do
    user = User.create!(name: "Joe Schmoe", preferences: { "alerts" => "on" })
    user.update!(preferences: { "alerts" => "off" })
    assert_equal user.versions.last.preferences, { "alerts" => "on" }
    user.destroy!
    user.versions.last.untrash!
    assert_equal user.reload.preferences, { "alerts" => "off" }
  end

  test "can assign hoardable_id when primary key is different" do
    tag = Tag.create!(name: "tug")
    tag.update!(name: "tag")
    tag_version = tag.versions.last
    assert_equal tag_version.hoardable_id, tag.id
    refute_equal tag_version.id, tag.id
  end

  test "can create multiple versions, and knows how to query at" do
    post
    datetime1 = DateTime.now
    update_post
    datetime2 = DateTime.now
    update_post(title: "Revert", status: :draft)
    datetime3 = DateTime.now
    post.destroy!
    datetime4 = DateTime.now
    assert_equal post.at(datetime1).title, "Headline"
    assert_equal PostVersion.at(datetime1).find_by(hoardable_id: post.id).title, "Headline"
    assert_equal post.at(datetime2).title, "New Headline"
    assert_equal PostVersion.at(datetime2).find_by(hoardable_id: post.id).title, "New Headline"
    assert_equal post.at(datetime3).title, "Revert"
    assert_equal PostVersion.at(datetime3).find_by(hoardable_id: post.id).title, "Revert"
    assert_equal post.trashed?, true
    assert_equal post.at(datetime4).title, "Revert"
    assert_nil PostVersion.at(datetime4).find_by(hoardable_id: post.id)
    assert_equal post.at(nil).title, "Revert"
  end

  test "can revert to version at a datetime" do
    post
    datetime1 = DateTime.now
    update_post
    datetime2 = DateTime.now
    reverted_post = post.revert_to!(datetime1)
    assert_equal reverted_post.title, "Headline"
    reverted_post = post.revert_to!(datetime2)
    assert_equal reverted_post.title, "New Headline"
    assert_equal post.versions.size, 3
    reverted_post = post.revert_to!(Time.now)
    assert_equal reverted_post.title, "New Headline"
    assert_equal post.versions.size, 3
  end

  test "cannot revert to version in the future" do
    assert_raises(Hoardable::Error) { post.revert_to!(DateTime.now + 1.day) }
  end

  test "cannot change hoardable_id" do
    assert_equal post.reload.hoardable_id, post.id
    if ActiveRecord.version >= Gem::Version.new("7.1")
      assert_raises ActiveRecord::ReadonlyAttributeError do
        post.update!(hoardable_id: 123)
      end
    end
    assert_raises(ActiveRecord::ActiveRecordError) { post.update_column(:hoardable_id, 123) }
    assert_raises(ActiveRecord::StatementInvalid) do
      post.class.connection.execute("UPDATE posts SET hoardable_id = 123")
    end
  end

  test "creates a version that is aware of relationships on parent model" do
    update_post
    version = post.versions.first
    assert_equal version.user, post.user
  end

  test "tests version is available in callbacks" do
    update_post
    assert post.hoardable_version_id
    assert_nil post.hoardable_version
  end

  test "it can halt transaction in after_versioned hook if necessary" do
    post = UnversionablePost.create!(title: "Unversionable", user: user)
    assert_raises(StandardError, "readonly") { post.update!(title: "Version?") }
    post.reload
    assert_equal post.title, "Unversionable"
    assert_equal post.versions.size, 0
  end

  test "it won’t persist an inserted version if the save fails" do
    post
    assert_raises(ActiveRecord::RecordInvalid) { post.update!(user: nil) }
    post.reload
    assert post.user
    assert_equal post.versions.size, 0
  end

  test "can be reverted from previous version" do
    attributes = post.reload.attributes.without("updated_at")
    update_post
    version = post.versions.first
    version.revert!
    assert_equal post.reload.attributes.without("updated_at"), attributes
    refute_equal post.updated_at, attributes["updated_at"]
  end

  test "creates a version on deletion and can be untrashed" do
    post_id = post.id
    attributes = post.reload.attributes.without("updated_at")
    post.destroy!
    assert post.trashed?
    assert_raises(ActiveRecord::RecordNotFound) { Post.find(post.id) }
    version = PostVersion.last
    assert_equal version.hoardable_id, post_id
    untrashed_post = version.untrash!
    assert_equal untrashed_post.attributes.without("updated_at"), attributes
    refute post.reload.trashed?
  end

  test "can trash and untrash a model multiple times, with each version creating unique post version IDs" do
    post_id = post.id
    Array.new(3) do
      post.reload.destroy!
      version = PostVersion.last
      version.untrash!
    end
    assert_equal post.reload.id, post_id
    assert_equal PostVersion.pluck("id").uniq.count, 6
  end

  test "can hook into after_reverted and after_untrashed callbacks" do
    assert_nil post.reverted
    assert_nil post.untrashed
    update_post
    version = post.versions.last
    reverted_post = version.revert!
    refute_nil reverted_post.reverted
    post.destroy!
    version = post.versions.trashed.last
    untrashed_post = version.untrash!
    refute_nil untrashed_post.untrashed
  end

  test "raises errors when trying to revert! or untrash! when not allowed" do
    update_post
    version = post.versions.last
    assert_raises(Hoardable::Error) { version.untrash! }
    post.destroy!
    version = post.versions.trashed.last
    assert_raises(Hoardable::Error) { version.revert! }
  end

  test "can query for trashed versions" do
    update_post
    assert_equal PostVersion.count, 1
    assert_equal PostVersion.trashed.size, 0
    post.destroy!
    assert_equal PostVersion.count, 2
    assert_equal PostVersion.trashed.size, 1
    version = PostVersion.trashed.last
    version.untrash!
    assert_equal PostVersion.count, 3
    assert_equal PostVersion.trashed.size, 0
  end

  test "does not create version on raised error" do
    assert_raises(ActiveModel::UnknownAttributeError) { update_post(non_existent_attribute: "wat") }
    assert_equal post.versions.size, 0
    assert_nil post.hoardable_version
  end

  test "does not create version when disabled" do
    Hoardable.enabled = false
    update_post
    assert_equal post.versions.size, 0
    Hoardable.enabled = true
  end

  test "does not create version when disabled within block" do
    Hoardable.with(enabled: false) do
      update_post
      assert_equal post.versions.size, 0
    end
  end

  test "does not create version when version_updates is false" do
    Hoardable.with(version_updates: false) do
      update_post
      assert_equal post.versions.size, 0
    end
  end

  test "can opt-out of versioning on deletion" do
    Hoardable.with(save_trash: false) do
      update_post
      assert_equal post.versions.size, 1
      post.destroy!
      assert_equal PostVersion.count, 0
    end
  end

  test "can disallow version_updates with Model configuration" do
    Post.with_hoardable_config(version_updates: false) do
      update_post
      assert_equal post.versions.size, 0
    end
  end

  test "can reset model level hoardable config to previous value" do
    Post.hoardable_config(version_updates: false)
    Post.with_hoardable_config(version_updates: true) do
      assert Post.hoardable_config[:version_updates]
    end
    assert_not Post.hoardable_config[:version_updates]

    # reset
    Post.hoardable_config(version_updates: true)
  end

  test "can reset hoardable version_updates to previous value" do
    Hoardable.version_updates = false
    Hoardable.with(version_updates: true) do
      assert Hoardable.version_updates
    end
    assert_not Hoardable.version_updates

    # reset
    Hoardable.version_updates = false
  end

  def expect_whodunit
    update_post
    version = post.versions.first
    assert_equal version.hoardable_whodunit, user.name
  end

  test "tracks whodunit as a string" do
    Hoardable.with(whodunit: user.name) { expect_whodunit }
  end

  test "tracks whodunit with a proc" do
    Hoardable.whodunit = -> { Current.user&.name }
    Current.user = user
    expect_whodunit
    Hoardable.whodunit = nil
    Current.user = nil
  end

  test "tracks meta" do
    meta = { "foo" => "bar" }
    Hoardable.with(meta: meta) do
      update_post
      version = post.versions.first
      assert_equal version.hoardable_meta, meta
    end
  end

  test "saves the changes hash along with the version" do
    update_post
    version = post.versions.first
    assert_equal version.changes.keys, %w[title status updated_at]
  end

  test "can unscope the tableoid clause in default scope to included versions of trashed sources" do
    post
    assert user.posts.exists?
    post.destroy!
    assert user.posts.empty?
    user_with_trashed_posts = UserWithTrashedPosts.find(user.id)
    assert user_with_trashed_posts.posts.exists?
  end

  test "can search for versions of resource on parent model" do
    Post.create!(title: "Another Headline", user: user)
    update_post
    assert_equal Post.count, 2
    assert_equal Post.include_versions.count, 3
    assert_equal Post.versions.count, 1
    post.destroy!
    assert_equal Post.count, 1
    assert_equal Post.include_versions.count, 3
    assert_equal Post.versions.count, 2
  end

  test "a comment can still point to a trashed post" do
    comment = post.comments.create!(body: "Comment 1")
    post.destroy!
    assert_equal comment.post, post
  end

  def create_comments_and_destroy_post
    post.comments.create!(body: "Comment 1")
    post.comments.create!(body: "Comment 2")
    post.destroy!
    PostVersion.trashed.find_by(hoardable_id: post.id)
  end

  test "recursively creates trashed versions with shared event_uuid" do
    update_post
    trashed_post = create_comments_and_destroy_post
    trashed_comments = CommentVersion.trashed.where(post_id: post.id)
    refute_equal post.versions.first.hoardable_event_uuid, trashed_post.hoardable_event_uuid
    assert_equal(
      trashed_post.hoardable_event_uuid,
      trashed_comments.first.hoardable_event_uuid,
      trashed_comments.second.hoardable_event_uuid
    )
  end

  test "can recursively untrash verisons with shared event_uuid" do
    trashed_post = create_comments_and_destroy_post
    assert_equal CommentVersion.trashed.where(post_id: post.id).size, 2
    assert_equal trashed_post.comments.size, 0
    trashed_post.untrash!
    untrashed_post = Post.find(post.id)
    assert_equal CommentVersion.trashed.size, 0
    assert_equal untrashed_post.comments.size, 2
  end

  test "creates a version class with a foreign key type that matches the primary key" do
    assert_equal Post.version_class.columns.find { |col| col.name == "hoardable_id" }.sql_type,
                 "bigint"
    assert_equal Book.version_class.columns.find { |col| col.name == "hoardable_id" }.sql_type,
                 "uuid"
  end

  test "can make versions of resources with UUID primary keys" do
    original_title = "Programming 101"
    book =
      Book.create!(title: original_title, library: Library.create!(name: "Town Center Library"))
    book_id = book.id
    datetime = Time.now
    new_title = "Programming 201"
    book.update!(title: new_title)
    assert_equal book.versions.last.title, original_title
    assert_equal book.at(datetime).title, original_title
    book.destroy!
    untrashed_book = BookVersion.trashed.find_by(hoardable_id: book_id).untrash!
    assert_equal untrashed_book.title, new_title
    assert_equal untrashed_book.id, book_id
  end

  test "does not save_trash when model is configured not to" do
    library = Library.create!(name: "Lib")
    library.update!(name: "Library")
    assert_equal library.versions.size, 1
    library.destroy!
    assert_equal Library.count, 0
    assert_equal LibraryVersion.count, 0
  end

  test "warns about missing created_at column" do
    bookmark = Bookmark.create!(name: "Paper")
    assert_raises(Hoardable::CreatedAtColumnMissingError) { bookmark.update!(name: "Ribbon") }
  end

  test "can return all versions and trash through parent class if necessary" do
    comment = post.comments.create!(body: "Comment 1")
    update_post
    datetime = Time.now
    post.destroy!
    assert_equal Post.count, 0
    assert_equal Comment.count, 0
    assert_equal post.comments.count, 0
    post_id = post.id
    Hoardable.at(datetime) do
      assert_equal Post.count, 1
      assert_equal Post.all.size, 1
      assert_equal Comment.count, 1
      assert_equal Comment.all.size, 1
      post = Post.find(post_id)
      assert comment.post
      assert_equal post.comments.count, 1
      assert_equal post.comments.size, 1
    end
  end

  test "can query the source model, including versions that were valid at a certain datetime" do
    post
    datetime1 = DateTime.now
    update_post
    datetime2 = DateTime.now
    update_post(title: "Revert", status: :draft)
    datetime3 = DateTime.now
    post.destroy!
    datetime4 = DateTime.now
    PostVersion.trashed.last.untrash!
    datetime5 = DateTime.now
    post = Post.last
    post.at(datetime2).revert!
    datetime6 = DateTime.now
    assert_equal Post.at(datetime1).pluck("title"), ["Headline"]
    assert_equal Post.at(datetime2).pluck("title"), ["New Headline"]
    assert_equal Post.at(datetime3).pluck("title"), ["Revert"]
    assert_equal Post.at(datetime4).pluck("title"), []
    assert_equal Post.at(datetime5).pluck("title"), ["Revert"]
    assert_equal Post.at(datetime6).pluck("title"), ["New Headline"]
  end

  test "returns hoardable records at the specified time with Hoardable.at" do
    comment = post.comments.create!(body: "Comment")
    datetime = DateTime.now
    comment.update!(body: "Comment Updated")
    post.update!(title: "Headline Updated")
    post_id = post.id
    Hoardable.at(datetime) do
      post = Post.find(post_id)
      assert_equal post.title, "Headline"
      assert_equal post.comments.first.body, "Comment"
    end
    Hoardable.at(DateTime.now) do
      post = Post.find(post_id)
      assert_equal post.title, "Headline Updated"
      assert_equal post.comments.first.body, "Comment Updated"
    end
  end

  test "can influence the upper bound of the temporal range with Hoardable.travel_to" do
    created_at = Time.now.utc - 10 * 86_400 # 10 days ago
    deleted_at = Time.now.utc - 5 * 86_400 # 5 days ago

    comment =
      post.comments.create!(body: "Comment 1", created_at: created_at, updated_at: created_at)

    Hoardable.travel_to(deleted_at) { comment.destroy! }

    temporal_range = CommentVersion.where(hoardable_id: comment.id).first._during

    assert_equal Comment.all.size, 0
    assert_equal temporal_range.max.round, deleted_at.round
  end

  test "will error if the upper bound of the temporal range with Hoardable.travel_to is less than the lower bound" do
    created_at = Time.now.utc - 10 * 86_400 # 10 days ago
    deleted_at = Time.now.utc - 12 * 86_400 # 12 days ago

    comment =
      post.comments.create!(body: "Comment 1", created_at: created_at, updated_at: created_at)

    Hoardable.travel_to(deleted_at) do
      assert_raises(Hoardable::InvalidTemporalUpperBoundError) { comment.destroy! }
    end

    assert_equal Comment.all.size, 1
  end

  test "cannot save a hoardable source record that is actually a version" do
    post
    datetime = DateTime.now
    post.update!(title: "Headline Updated")
    post_id = post.id
    Hoardable.at(datetime) do
      post = Post.find(post_id)
      assert_raises(ActiveRecord::StatementInvalid) { post.update!(title: "Hmmm") }
      assert_equal post.reload.title, "Headline"
    end
    assert_equal post.reload.versions.size, 1
  end

  test "can return hoardable records at a specified time with an ID of a record that is destroyed" do
    post
    datetime = DateTime.now
    post.destroy!
    post_id = post.id
    Hoardable.at(datetime) { assert Post.find(post_id) }
    Hoardable.at(DateTime.now) do
      assert_raises(ActiveRecord::RecordNotFound) { Post.find(post_id) }
    end
  end

  test "can return hoardable records at a specified time with multiple IDs" do
    post
    post2 = Post.create!(title: "Number 2", user: user)
    datetime = DateTime.now
    post.update!(title: "Foo")
    post2.update!(title: "Bar")
    Hoardable.at(datetime) do
      assert_equal Post.find([post.id, post2.id]).pluck("title").sort, ["Headline", "Number 2"].sort
    end
  end

  test "can return hoardable records via a has many through relationship" do
    post = Post.create!(user: user, title: "Title")
    comment = post.comments.create!(body: "Comment")
    comment.likes.create!
    comment.likes.create!
    datetime = DateTime.now
    comment.update!(body: "Updated")
    comment.likes.create!
    comment.likes.create!
    post_id = post.id
    Hoardable.at(datetime) do
      post = Post.find(post_id)
      assert_equal post.comments.pluck("body"), ["Comment"]
      comment = post.comments.first
      assert_equal 2, Like.count
      assert_equal 2, Like.all.size
      assert_equal 2, comment.likes.count
      assert_equal 2, comment.likes.size
      assert_equal 2, post.likes.count
      assert_equal 2, post.likes.size
    end
  end

  test "can returns a set of comment versions at specified time" do
    comment1 = post.comments.create!(body: "Comment 1")
    comment2 = post.comments.create!(body: "Comment 2")
    comment3 = post.comments.create!(body: "Comment 3")
    datetime = DateTime.now
    comment2.destroy!
    Hoardable.at(datetime) do
      assert_equal(post.reload.comment_ids, [comment1.id, comment3.id, comment2.versions.last.id])
      assert_equal(
        post.reload.comments.map(&:hoardable_id),
        [comment1.id, comment3.id, comment2.id]
      )
    end
    assert_equal(post.reload.comment_ids, post.reload.comments.map(&:hoardable_id))
  end

  test "can return hoardable results with has one relationship" do
    profile = Profile.create!(user: user, email: "email@example.com")
    datetime1 = DateTime.now
    profile.update!(email: "foo@bar.com")
    datetime2 = DateTime.now
    profile.destroy!
    datetime3 = DateTime.now
    assert_nil user.reload.profile
    Hoardable.at(datetime1) { assert_equal user.profile.email, "email@example.com" }
    Hoardable.at(datetime2) { assert_equal user.profile.email, "foo@bar.com" }
    Hoardable.at(datetime3) { assert_nil user.profile }
  end

  test "creates rich text record for versions" do
    post = PostWithRichText.create!(title: "Title", content: "<div>Hello World</div>", user: user)
    datetime = DateTime.now
    post.update!(content: "<div>Goodbye Cruel World</div>")
    assert_equal post.content.versions.size, 1
    assert_equal post.content.to_plain_text, "Goodbye Cruel World"
    assert_equal post.content.versions.first.body.to_plain_text, "Hello World"
    Hoardable.at(datetime) { assert_equal post.content.to_plain_text, "Hello World" }
  end

  test "can access rich text record through version" do
    post = PostWithRichText.create!(title: "Title", content: "<div>Hello World</div>", user: user)
    post.update!(content: "<div>Goodbye Cruel World</div>")
    post.update!(title: "New Title")
    post.update!(content: "<div>Ahh, Welcome Back</div>")
    assert_equal post.versions.first.content.body.to_plain_text, "Hello World"
    assert_equal post.versions.second.content.body.to_plain_text, "Goodbye Cruel World"
    assert_equal post.versions.third.content.body.to_plain_text, "Goodbye Cruel World"
  end

  test "returns proper rich text when unpersisted and given invalid datetime" do
    post = PostWithRichText.new
    assert_equal post.at(DateTime.now).content.to_plain_text, ""
    assert_equal post.at(nil).content.to_plain_text, ""
  end

  if SUPPORTS_ENCRYPTED_ACTION_TEXT
    test "creates encrypted rich text record for versions" do
      post =
        PostWithEncryptedRichText.create!(
          title: "Title",
          content: "<div>Hello World</div>",
          user: user
        )
      datetime = DateTime.now
      post.update!(content: "<div>Goodbye Cruel World</div>")
      assert_equal post.content.versions.size, 1
      assert_equal post.content.to_plain_text, "Goodbye Cruel World"
      assert_equal post.content.versions.first.body.to_plain_text, "Hello World"
      Hoardable.at(datetime) { assert_equal post.content.to_plain_text, "Hello World" }
      assert post.content.encrypted_attribute?("body")
    end
  end

  test "has_hoardable_rich_text works" do
    profile =
      Profile.create!(user: user, email: "email@example.com", life_story: "<div>woke up</div>")
    datetime = DateTime.now
    profile.update!(life_story: "<div>went to sleep</div>")
    assert_equal "woke up", profile.at(datetime).life_story.to_plain_text
  end

  if SUPPORTS_ENCRYPTED_ACTION_TEXT
    test "has_hoardable_rich_text works for encrypted rich text" do
      profile =
        Profile.create!(user: user, email: "email@example.com", diary: "<div>i'm happy</div>")
      datetime = DateTime.now
      profile.update!(diary: "<div>i'm sad</div>")
      assert_equal "i'm happy", profile.at(datetime).diary.to_plain_text
      assert profile.diary.encrypted_attribute?("body")
    end
  end

  test "returns correct polymoprhic association via temporal has one relationship" do
    user = User.create!(name: "Joe Schmoe", bio: "<div>Bio</div>")
    post = PostWithRichText.create!(title: "Title", content: "<div>Content</div>", user: user)
    datetime = DateTime.now
    user.update!(bio: "<div>Still Bio</div>")
    post.update!(content: "<div>Still Content</div>")
    assert_equal post.id, user.id
    assert_equal post.versions.last.content.to_plain_text, "Content"
    assert_equal user.versions.last.bio.to_plain_text, "Bio"
    assert_equal post.at(datetime).content.to_plain_text, "Content"
    assert_equal user.at(datetime).bio.to_plain_text, "Bio"
  end

  test "returns correct rich text for model with multiple rich texts" do
    post =
      PostWithRichText.create!(
        title: "Title",
        content: "<div>Content</div>",
        description: "<div>Description</div>",
        user: user
      )
    datetime = DateTime.now
    post.update!(content: "<div>New Content</div>", description: "<div>New Description</div>")
    assert_equal post.at(datetime).content.to_plain_text, "Content"
    assert_equal post.at(datetime).description.to_plain_text, "Description"
    assert_equal post.versions.last.content.to_plain_text, "Content"
    assert_equal post.versions.last.description.to_plain_text, "Description"
  end

  test "does not create versions without hoardable keyword" do
    post =
      PostWithUnhoardableRichText.create!(
        title: "Title",
        content: "<div>Hello World</div>",
        user: user
      )
    assert_instance_of ActionText::RichText, post.content
    assert_raises(StandardError) { post.content.versions }
  end

  test "applies ONLY clause on joined relationship" do
    assert_equal(
      "SELECT \"users\".* FROM ONLY users INNER JOIN ONLY \"posts\" ON \"posts\".\"user_id\" = \"users\".\"id\"",
      User.joins(:posts).to_sql
    )
    post
    refute_empty user.posts
    refute_empty User.joins(:posts)
    post.destroy!
    assert_empty user.posts
    assert_empty User.joins(:posts)
  end

  test "applies ONLY clause on joined relationship with aliased name" do
    assert_equal(
      "SELECT \"users\".* FROM \"users\" INNER JOIN ONLY \"profiles\" \"bio\" ON \"bio\".\"user_id\" = \"users\".\"id\" WHERE \"bio\".\"id\" = 999",
      UserWithTrashedPosts.joins(:bio).where(bio: { id: 999 }).to_sql
    )
  end

  test "can version and revert an STI model" do
    library = Library.create!(name: "Library")
    masterpiece = Masterpiece.create!(title: "Masterpiece 1", library: library)
    assert_equal "Masterpiece 1!", masterpiece.title
    masterpiece.update!(title: "Masterpiece 2")
    masterpiece_version = masterpiece.versions.first
    assert_equal "Masterpiece 1!", masterpiece_version.title

    masterpiece_version.revert!
    assert_equal "Masterpiece 1!", masterpiece_version.title
  end

  test "doesn’t mix versions of base and inheriting records" do
    library = Library.create!(name: "Library")
    book = Book.create!(title: "Boo", library: library)
    masterpiece = Masterpiece.create!(title: "Masterpiec", library: library)
    book.update!(title: "Book")

    assert_equal 1, BookVersion.count
    assert_equal 0, MasterpieceVersion.count
    assert_equal 1, book.versions.count
    assert_equal 0, masterpiece.versions.count

    masterpiece.update!(title: "Masterpiece")
    assert_equal 1, BookVersion.count
    assert_equal 1, MasterpieceVersion.count
    assert_equal 1, book.versions.count
    assert_equal 1, masterpiece.versions.count
  end

  test "applies ONLY when performing update_all on Hoardable model" do
    tag = Tag.create!(name: "Library")
    tag.destroy!
    trashed_tag = Tag.version_class.trashed.find_sole_by(hoardable_id: tag.id)

    trashed_tag.untrash!

    assert_equal(1, Tag.count)
    assert_equal(2, Tag.version_class.count)
    assert_equal(1, Tag.update_all(name: "New name"))

    assert_equal("New name", tag.reload.name)
    assert_equal("Library", trashed_tag.name)
  end
end
