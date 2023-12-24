# frozen_string_literal: true

require "helper"

class TestModel < Minitest::Test
  extend Minitest::Spec::DSL

  before do
    ActiveRecord::Base.connection.tables.each do |table|
      ActiveRecord::Base.connection.execute("TRUNCATE #{table} RESTART IDENTITY CASCADE")
    end
  end

  let(:user) { User.create!(name: "Justin") }

  let(:post) { Post.create!(title: "Headline", user: user) }

  def update_post(attributes = { title: "New Headline", status: :live })
    post.update!(attributes)
    assert_equal post.status.to_sym, attributes[:status]
    assert_equal post.title, attributes[:title]
  end

  it "can do the very first readme example" do
    assert_equal post.versions.size, 0
    update_post
    assert_equal post.reload.versions.size, 1
    post.destroy!
    assert post.trashed?
    assert_equal post.versions.size, 2
    assert_raises(ActiveRecord::RecordNotFound) { Post.find(post.id) }
  end

  it "creates a version with previous state and generated columns" do
    assert_equal post.versions.size, 0
    update_post
    assert_equal post.reload.versions.size, 1
    version = post.versions.first
    assert_equal version.status, "draft"
    assert_equal version.title, "Headline"
    assert_equal version.lowercase_title, "headline"
  end

  it "uses current db version and not the current ruby attribute value for version" do
    post.title = "Draft Headline"
    update_post
    assert_equal post.versions.size, 1
    version = post.versions.first
    assert_equal version.title, "Headline"
  end

  it "creates read-only versions that do not themselves have versions" do
    update_post
    version = post.versions.first
    assert_raises(ActiveRecord::ReadOnlyRecord) { version.update!(title: "Rewriting History") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { version.destroy! }
    assert_raises(ActiveRecord::AssociationNotFoundError) { version.versions }
  end

  it "preserves created_at timestamps, expects during tsrange is set" do
    update_post
    version = post.versions.first
    assert_equal post.created_at, version.created_at
    assert version._during
  end

  it "knows how to dynamically create namespaced version classes" do
    post = Hoardable::Post.create!(title: "Hi", user: user)
    post.update!(title: "Bye")
    assert_instance_of Hoardable::PostVersion, post.versions.first
  end

  it "works with serialized attributes" do
    user = User.create!(name: "Joe Schmoe", preferences: { "alerts" => "on" })
    user.update!(preferences: { "alerts" => "off" })
    assert_equal user.versions.last.preferences, { "alerts" => "on" }
    user.destroy!
    user.versions.last.untrash!
    assert_equal user.reload.preferences, { "alerts" => "off" }
  end

  it "can assign hoardable_id when primary key is different" do
    tag = Tag.create!(name: "tug")
    tag.update!(name: "tag")
    tag_version = tag.versions.last
    assert_equal tag_version.hoardable_id, tag.id
    refute_equal tag_version.id, tag.id
  end

  it "can create multiple versions, and knows how to query at" do
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

  it "can revert to version at a datetime" do
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

  it "cannot revert to version in the future" do
    assert_raises(Hoardable::Error) { post.revert_to!(DateTime.now + 1.day) }
  end

  it "cannot change hoardable_id" do
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

  it "creates a version that is aware of relationships on parent model" do
    update_post
    version = post.versions.first
    assert_equal version.user, post.user
  end

  it "tests version is available in callbacks" do
    update_post
    assert post.hoardable_version_id
    assert_nil post.hoardable_version
  end

  it "it can halt transaction in after_versioned hook if necessary" do
    post = UnversionablePost.create!(title: "Unversionable", user: user)
    assert_raises(StandardError, "readonly") { post.update!(title: "Version?") }
    post.reload
    assert_equal post.title, "Unversionable"
    assert_equal post.versions.size, 0
  end

  it "it won’t persist an inserted version if the save fails" do
    post
    assert_raises(ActiveRecord::RecordInvalid) { post.update!(user: nil) }
    post.reload
    assert post.user
    assert_equal post.versions.size, 0
  end

  it "can be reverted from previous version" do
    attributes = post.reload.attributes.without("updated_at")
    update_post
    version = post.versions.first
    version.revert!
    assert_equal post.reload.attributes.without("updated_at"), attributes
    refute_equal post.updated_at, attributes["updated_at"]
  end

  it "creates a version on deletion and can be untrashed" do
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

  it "can trash and untrash a model multiple times, with each version creating unique post version IDs" do
    post_id = post.id
    Array.new(3) do
      post.reload.destroy!
      version = PostVersion.last
      version.untrash!
    end
    assert_equal post.reload.id, post_id
    assert_equal PostVersion.pluck("id").uniq.count, 6
  end

  it "can hook into after_reverted and after_untrashed callbacks" do
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

  it "raises errors when trying to revert! or untrash! when not allowed" do
    update_post
    version = post.versions.last
    assert_raises(Hoardable::Error) { version.untrash! }
    post.destroy!
    version = post.versions.trashed.last
    assert_raises(Hoardable::Error) { version.revert! }
  end

  it "can query for trashed versions" do
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

  it "does not create version on raised error" do
    assert_raises(ActiveModel::UnknownAttributeError) { update_post(non_existent_attribute: "wat") }
    assert_equal post.versions.size, 0
    assert_nil post.hoardable_version
  end

  it "does not create version when disabled" do
    Hoardable.enabled = false
    update_post
    assert_equal post.versions.size, 0
    Hoardable.enabled = true
  end

  it "does not create version when disabled within block" do
    Hoardable.with(enabled: false) do
      update_post
      assert_equal post.versions.size, 0
    end
  end

  it "does not create version when version_updates is false" do
    Hoardable.with(version_updates: false) do
      update_post
      assert_equal post.versions.size, 0
    end
  end

  it "can opt-out of versioning on deletion" do
    Hoardable.with(save_trash: false) do
      update_post
      assert_equal post.versions.size, 1
      post.destroy!
      assert_equal PostVersion.count, 0
    end
  end

  it "can disallow version_updates with Model configuration" do
    Post.with_hoardable_config(version_updates: false) do
      update_post
      assert_equal post.versions.size, 0
    end
  end

  def expect_whodunit
    update_post
    version = post.versions.first
    assert_equal version.hoardable_whodunit, user.name
  end

  it "tracks whodunit as a string" do
    Hoardable.with(whodunit: user.name) { expect_whodunit }
  end

  it "tracks whodunit with a proc" do
    Hoardable.whodunit = -> { Current.user&.name }
    Current.user = user
    expect_whodunit
    Hoardable.whodunit = nil
    Current.user = nil
  end

  it "tracks meta" do
    meta = { "foo" => "bar" }
    Hoardable.with(meta: meta) do
      update_post
      version = post.versions.first
      assert_equal version.hoardable_meta, meta
    end
  end

  it "saves the changes hash along with the version" do
    update_post
    version = post.versions.first
    assert_equal version.changes.keys, %w[title status updated_at]
  end

  it "can unscope the tableoid clause in default scope to included versions of trashed sources" do
    post
    assert user.posts.exists?
    post.destroy!
    assert user.posts.empty?
    user_with_trashed_posts = UserWithTrashedPosts.find(user.id)
    assert user_with_trashed_posts.posts.exists?
  end

  it "can search for versions of resource on parent model" do
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

  it "a comment can still point to a trashed post" do
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

  it "recursively creates trashed versions with shared event_uuid" do
    update_post
    trashed_post = create_comments_and_destroy_post
    trashed_comments = CommentVersion.trashed.where(post_id: post.id)
    refute_equal post.versions.first.hoardable_event_uuid, trashed_post.hoardable_event_uuid
    assert_equal(
      trashed_post.hoardable_event_uuid,
      trashed_comments.first.hoardable_event_uuid,
      trashed_comments.second.hoardable_event_uuid,
    )
  end

  it "can recursively untrash verisons with shared event_uuid" do
    trashed_post = create_comments_and_destroy_post
    assert_equal CommentVersion.trashed.where(post_id: post.id).size, 2
    assert_equal trashed_post.comments.size, 0
    trashed_post.untrash!
    untrashed_post = Post.find(post.id)
    assert_equal CommentVersion.trashed.size, 0
    assert_equal untrashed_post.comments.size, 2
  end

  it "creates a version class with a foreign key type that matches the primary key" do
    assert_equal Post.version_class.columns.find { |col| col.name == "hoardable_id" }.sql_type, "bigint"
    assert_equal Book.version_class.columns.find { |col| col.name == "hoardable_id" }.sql_type, "uuid"
  end

  it "can make versions of resources with UUID primary keys" do
    original_title = "Programming 101"
    book = Book.create!(title: original_title, library: Library.create!(name: "Town Center Library"))
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

  it "does not save_trash when model is configured not to" do
    library = Library.create!(name: "Lib")
    library.update!(name: "Library")
    assert_equal library.versions.size, 1
    library.destroy!
    assert_equal Library.count, 0
    assert_equal LibraryVersion.count, 0
  end

  it "warns about missing created_at column" do
    bookmark = Bookmark.create!(name: "Paper")
    assert_raises(Hoardable::CreatedAtColumnMissingError) { bookmark.update!(name: "Ribbon") }
  end

  it "can return all versions and trash through parent class if necessary" do
    comment = post.comments.create!(body: "Comment 1")
    update_post
    datetime = Time.now
    post.destroy!
    assert_equal Post.all.size, 0
    assert_equal Comment.all.size, 0
    post_id = post.id
    Hoardable.at(datetime) do
      assert_equal Post.all.size, 1
      assert_equal Comment.all.size, 1
      post = Post.find(post_id)
      assert comment.post
      assert_equal post.comments.size, 1
    end
  end

  it "can query the source model, including versions that were valid at a certain datetime" do
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

  it "returns hoardable records at the specified time with Hoardable.at" do
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

  it "cannot save a hoardable source record that is actually a version" do
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

  it "can return hoardable records at a specified time with an ID of a record that is destroyed" do
    post
    datetime = DateTime.now
    post.destroy!
    post_id = post.id
    Hoardable.at(datetime) { assert Post.find(post_id) }
    Hoardable.at(DateTime.now) { assert_raises(ActiveRecord::RecordNotFound) { Post.find(post_id) } }
  end

  it "can return hoardable records at a specified time with multiple IDs" do
    post
    post2 = Post.create!(title: "Number 2", user: user)
    datetime = DateTime.now
    post.update!(title: "Foo")
    post2.update!(title: "Bar")
    Hoardable.at(datetime) do
      assert_equal Post.find([post.id, post2.id]).pluck("title").sort, ["Headline", "Number 2"].sort
    end
  end

  it "can return hoardable records via a has many through relationship" do
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
      assert_equal 2, Like.all.size
      assert_equal 2, comment.likes.size
      assert_equal 2, post.likes.size
    end
  end

  it "can returns a set of comment versions at specified time" do
    comment1 = post.comments.create!(body: "Comment 1")
    comment2 = post.comments.create!(body: "Comment 2")
    comment3 = post.comments.create!(body: "Comment 3")
    datetime = DateTime.now
    comment2.destroy!
    Hoardable.at(datetime) do
      assert_equal(post.reload.comment_ids, [comment1.id, comment3.id, comment2.versions.last.id])
      assert_equal(post.reload.comments.map(&:hoardable_id), [comment1.id, comment3.id, comment2.id])
    end
    assert_equal(post.reload.comment_ids, post.reload.comments.map(&:hoardable_id))
  end

  it "can return hoardable results with has one relationship" do
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

  it "creates rich text record for versions" do
    post = PostWithRichText.create!(title: "Title", content: "<div>Hello World</div>", user: user)
    datetime = DateTime.now
    post.update!(content: "<div>Goodbye Cruel World</div>")
    assert_equal post.content.versions.size, 1
    assert_equal post.content.to_plain_text, "Goodbye Cruel World"
    assert_equal post.content.versions.first.body.to_plain_text, "Hello World"
    Hoardable.at(datetime) { assert_equal post.content.to_plain_text, "Hello World" }
  end

  it "can access rich text record through version" do
    post = PostWithRichText.create!(title: "Title", content: "<div>Hello World</div>", user: user)
    post.update!(content: "<div>Goodbye Cruel World</div>")
    post.update!(title: "New Title")
    post.update!(content: "<div>Ahh, Welcome Back</div>")
    assert_equal post.versions.first.content.body.to_plain_text, "Hello World"
    assert_equal post.versions.second.content.body.to_plain_text, "Goodbye Cruel World"
    assert_equal post.versions.third.content.body.to_plain_text, "Goodbye Cruel World"
  end

  it "returns proper rich text when unpersisted and given invalid datetime" do
    post = PostWithRichText.new
    assert_equal post.at(DateTime.now).content.to_plain_text, ""
    assert_equal post.at(nil).content.to_plain_text, ""
  end

  if SUPPORTS_ENCRYPTED_ACTION_TEXT
    it "creates encrypted rich text record for versions" do
      post = PostWithEncryptedRichText.create!(title: "Title", content: "<div>Hello World</div>", user: user)
      datetime = DateTime.now
      post.update!(content: "<div>Goodbye Cruel World</div>")
      assert_equal post.content.versions.size, 1
      assert_equal post.content.to_plain_text, "Goodbye Cruel World"
      assert_equal post.content.versions.first.body.to_plain_text, "Hello World"
      Hoardable.at(datetime) { assert_equal post.content.to_plain_text, "Hello World" }
      assert post.content.encrypted_attribute?("body")
    end
  end

  it "returns correct polymoprhic association via temporal has one relationship" do
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

  it "returns correct rich text for model with multiple rich texts" do
    post =
      PostWithRichText.create!(
        title: "Title",
        content: "<div>Content</div>",
        description: "<div>Description</div>",
        user: user,
      )
    datetime = DateTime.now
    post.update!(content: "<div>New Content</div>", description: "<div>New Description</div>")
    assert_equal post.at(datetime).content.to_plain_text, "Content"
    assert_equal post.at(datetime).description.to_plain_text, "Description"
    assert_equal post.versions.last.content.to_plain_text, "Content"
    assert_equal post.versions.last.description.to_plain_text, "Description"
  end

  it "does not create versions without hoardable keyword" do
    post = PostWithUnhoardableRichText.create!(title: "Title", content: "<div>Hello World</div>", user: user)
    assert_instance_of ActionText::RichText, post.content
    assert_raises(StandardError) { post.content.versions }
  end
end
