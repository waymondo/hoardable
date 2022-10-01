# frozen_string_literal: true

require 'test_helper'

class TestModel < Minitest::Test
  extend Minitest::Spec::DSL

  before { truncate_db }

  let(:user) { User.create!(name: 'Justin') }

  let(:post) { Post.create!(title: 'Headline', user: user) }

  def update_post(attributes = { title: 'New Headline', status: :live })
    post.update!(attributes)
    assert_equal post.status.to_sym, attributes[:status]
    assert_equal post.title, attributes[:title]
  end

  it 'can do the very first readme example' do
    assert_equal post.versions.size, 0
    update_post
    assert_equal post.reload.versions.size, 1
    post.destroy!
    assert post.trashed?
    assert_equal post.versions.size, 2
    assert_raises(ActiveRecord::RecordNotFound) { Post.find(post.id) }
  end

  it 'creates a version with previous state' do
    assert_equal post.versions.size, 0
    update_post
    assert_equal post.reload.versions.size, 1
    version = post.versions.first
    assert_equal version.status, 'draft'
    assert_equal version.title, 'Headline'
  end

  it 'uses current db version and not the current ruby attribute value for version' do
    post.title = 'Draft Headline'
    update_post
    assert_equal post.versions.size, 1
    version = post.versions.first
    assert_equal version.title, 'Headline'
  end

  it 'creates read-only versions that do not themselves have versions' do
    update_post
    version = post.versions.first
    assert_raises(ActiveRecord::ReadOnlyRecord) { version.update!(title: 'Rewriting History') }
    assert_raises(ActiveRecord::ReadOnlyRecord) { version.destroy! }
    assert_raises(ActiveRecord::AssociationNotFoundError) { version.versions }
  end

  it 'preserves created_at timestamps, expects during tsrange is set' do
    update_post
    version = post.versions.first
    assert_equal post.created_at, version.created_at
    assert version._during
  end

  it 'can create multiple versions, and knows how to query "at"' do
    post
    datetime1 = DateTime.now
    update_post
    datetime2 = DateTime.now
    update_post(title: 'Revert', status: :draft)
    datetime3 = DateTime.now
    post.destroy!
    datetime4 = DateTime.now
    assert_equal post.at(datetime1).title, 'Headline'
    assert_equal PostVersion.at(datetime1).find_by(hoardable_source_id: post.id).title, 'Headline'
    assert_equal post.at(datetime2).title, 'New Headline'
    assert_equal PostVersion.at(datetime2).find_by(hoardable_source_id: post.id).title, 'New Headline'
    assert_equal post.at(datetime3).title, 'Revert'
    assert_equal PostVersion.at(datetime3).find_by(hoardable_source_id: post.id).title, 'Revert'
    assert_equal post.trashed?, true
    assert_equal post.at(datetime4).title, 'Revert'
    assert_nil PostVersion.at(datetime4).find_by(hoardable_source_id: post.id)
  end

  it 'can revert to version at a datetime' do
    post
    datetime1 = DateTime.now
    update_post
    datetime2 = DateTime.now
    reverted_post = post.revert_to!(datetime1)
    assert_equal reverted_post.title, 'Headline'
    reverted_post = post.revert_to!(datetime2)
    assert_equal reverted_post.title, 'New Headline'
    assert_equal post.versions.size, 3
    reverted_post = post.revert_to!(Time.now)
    assert_equal reverted_post.title, 'New Headline'
    assert_equal post.versions.size, 3
  end

  it 'cannot revert to version in the future' do
    assert_raises(Hoardable::Error) { post.revert_to!(DateTime.now + 1.day) }
  end

  it 'creates a version that is aware of relationships on parent model' do
    update_post
    version = post.versions.first
    assert_equal version.user, post.user
  end

  it 'tests version is available in callbacks' do
    update_post
    assert post.hoardable_version_id
    assert_nil post.hoardable_version
  end

  it 'can be reverted from previous version' do
    attributes = post.attributes.without('updated_at')
    update_post
    version = post.versions.first
    version.revert!
    assert_equal post.attributes.without('updated_at'), attributes
    refute_equal post.updated_at, attributes['updated_at']
  end

  it 'creates a version on deletion and can be untrashed' do
    post_id = post.id
    attributes = post.attributes.without('updated_at')
    post.destroy!
    assert post.trashed?
    assert_raises(ActiveRecord::RecordNotFound) { Post.find(post.id) }
    version = PostVersion.last
    assert_equal version.hoardable_source_id, post_id
    untrashed_post = version.untrash!
    assert_equal untrashed_post.attributes.without('updated_at'), attributes
    refute post.reload.trashed?
  end

  it 'can trash and untrash a model multiple times, with each version creating unique post version IDs' do
    post_id = post.id
    Array.new(3) do
      post.reload.destroy!
      version = PostVersion.last
      version.untrash!
    end
    assert_equal post.reload.id, post_id
    assert_equal PostVersion.pluck('id').uniq.count, 6
  end

  it 'can hook into after_reverted and after_untrashed callbacks' do
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

  it 'raises errors when trying to revert! or untrash! when not allowed' do
    update_post
    version = post.versions.last
    assert_raises(Hoardable::Error) { version.untrash! }
    post.destroy!
    version = post.versions.trashed.last
    assert_raises(Hoardable::Error) { version.revert! }
  end

  it 'can query for trashed versions' do
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

  it 'does not create version on raised error' do
    assert_raises(ActiveModel::UnknownAttributeError) { update_post(non_existent_attribute: 'wat') }
    assert_equal post.versions.size, 0
    assert_nil post.hoardable_version
  end

  it 'does not create version when disabled' do
    Hoardable.enabled = false
    update_post
    assert_equal post.versions.size, 0
    Hoardable.enabled = true
  end

  it 'does not create version when disabled within block' do
    Hoardable.with(enabled: false) do
      update_post
      assert_equal post.versions.size, 0
    end
  end

  it 'does not create version when version_updates is false' do
    Hoardable.with(version_updates: false) do
      update_post
      assert_equal post.versions.size, 0
    end
  end

  it 'can opt-out of versioning on deletion' do
    Hoardable.with(save_trash: false) do
      update_post
      assert_equal post.versions.size, 1
      post.destroy!
      assert_equal PostVersion.count, 0
    end
  end

  it 'can disallow version_updates with Model configuration' do
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

  it 'tracks whodunit as a string' do
    Hoardable.with(whodunit: user.name) do
      expect_whodunit
    end
  end

  it 'tracks whodunit with a proc' do
    Hoardable.whodunit = -> { Current.user&.name }
    Current.user = user
    expect_whodunit
    Hoardable.whodunit = nil
    Current.user = nil
  end

  it 'tracks note and meta' do
    note = 'Oopsie'
    meta = { 'foo' => 'bar' }
    Hoardable.with(note: note, meta: meta) do
      update_post
      version = post.versions.first
      assert_equal version.hoardable_note, note
      assert_equal version.hoardable_meta, meta
    end
  end

  it 'saves the changes hash along with the version' do
    update_post
    version = post.versions.first
    assert_equal version.changes.keys, %w[title status updated_at]
  end

  it 'can unscope the tableoid clause in default scope to included versions of trashed sources' do
    post
    assert user.posts.exists?
    post.destroy!
    assert user.posts.size.zero?
    user_with_trashed_posts = UserWithTrashedPosts.find(user.id)
    assert user_with_trashed_posts.posts.exists?
  end

  it 'can search for versions of resource on parent model' do
    Post.create!(title: 'Another Headline', user: user)
    update_post
    assert_equal Post.count, 2
    assert_equal Post.include_versions.count, 3
    assert_equal Post.versions.count, 1
    post.destroy!
    assert_equal Post.count, 1
    assert_equal Post.include_versions.count, 3
    assert_equal Post.versions.count, 2
  end

  it 'a comment can still point to a trashed post' do
    comment = post.comments.create!(body: 'Comment 1')
    post.destroy!
    assert_equal comment.post, post
  end

  def create_comments_and_destroy_post
    post.comments.create!(body: 'Comment 1')
    post.comments.create!(body: 'Comment 2')
    post.destroy!
    PostVersion.trashed.find_by(hoardable_source_id: post.id)
  end

  it 'recursively creates trashed versions with shared event_uuid' do
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

  it 'can recursively untrash verisons with shared event_uuid' do
    trashed_post = create_comments_and_destroy_post
    assert_equal CommentVersion.trashed.where(post_id: post.id).size, 2
    assert_equal post.comments.size, 0
    trashed_post.untrash!
    untrashed_post = Post.find(post.id)
    assert_equal CommentVersion.trashed.size, 0
    assert_equal untrashed_post.comments.size, 2
  end

  it 'creates a version class with a foreign key type that matches the primary key' do
    assert_equal Post.version_class.columns.find { |col| col.name == 'hoardable_source_id' }.sql_type, 'bigint'
    assert_equal Book.version_class.columns.find { |col| col.name == 'hoardable_source_id' }.sql_type, 'uuid'
  end

  it 'can make versions of resources with UUID primary keys' do
    original_title = 'Programming 101'
    book = Book.create!(title: original_title, library: Library.create!(name: 'Town Center Library'))
    book_id = book.id
    datetime = Time.now
    new_title = 'Programming 201'
    book.update!(title: new_title)
    assert_equal book.versions.last.title, original_title
    assert_equal book.at(datetime).title, original_title
    book.destroy!
    untrashed_book = BookVersion.trashed.find_by(hoardable_source_id: book_id).untrash!
    assert_equal untrashed_book.title, new_title
    assert_equal untrashed_book.id, book_id
  end

  it 'does not save_trash when model is configured not to' do
    library = Library.create!(name: 'Lib')
    library.update!(name: 'Library')
    assert_equal library.versions.size, 1
    library.destroy!
    assert_equal Library.count, 0
    assert_equal LibraryVersion.count, 0
  end

  it 'warns about missing created_at column' do
    bookmark = Bookmark.create!(name: 'Paper')
    assert_output(/'bookmarks' does not have a 'created_at' column/) do
      bookmark.update!(name: 'Ribbon')
    end
  end

  it 'does not warn about missing created_at column when disabled' do
    bookmark = Bookmark.create!(name: 'Paper')
    Hoardable.with(warn_on_missing_created_at_column: false) do
      assert_output('') do
        bookmark.update!(name: 'Ribbon')
      end
    end
  end

  it 'can return all versions and trash through parent class if necessary' do
    comment = post.comments.create!(body: 'Comment 1')
    update_post
    post.destroy!
    assert_equal Post.all.size, 0
    assert_equal Comment.all.size, 0
    Hoardable.with(return_everything: true) do
      assert_equal Post.all.size, 2
      assert_equal PostVersion.all.size, 2
      assert_equal Comment.all.size, 1
      assert_equal CommentVersion.all.size, 1
      assert_equal comment.post, post
    end
  end

  it 'can still create models, versions and trash when returning everything' do
    Hoardable.with(return_everything: true) do
      update_post
      post.destroy!
      Post.create!(title: 'Another Headline', user: user)
      assert_equal Post.all.size, 3
      assert_equal PostVersion.all.size, 2
    end
  end

  it 'can query the source model, including versions that were valid at a certain datetime' do
    post
    datetime1 = DateTime.now
    update_post
    datetime2 = DateTime.now
    update_post(title: 'Revert', status: :draft)
    datetime3 = DateTime.now
    post.destroy!
    datetime4 = DateTime.now
    PostVersion.trashed.last.untrash!
    datetime5 = DateTime.now
    post = Post.last
    post.at(datetime2).revert!
    datetime6 = DateTime.now
    assert_equal Post.at(datetime1).pluck('title'), ['Headline']
    assert_equal Post.at(datetime2).pluck('title'), ['New Headline']
    assert_equal Post.at(datetime3).pluck('title'), ['Revert']
    assert_equal Post.at(datetime4).pluck('title'), []
    assert_equal Post.at(datetime5).pluck('title'), ['Revert']
    assert_equal Post.at(datetime6).pluck('title'), ['New Headline']
  end
end
