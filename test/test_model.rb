# frozen_string_literal: true

require 'test_helper'

class Post < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :user
  attr_reader :hoardable_operation, :reverted, :hoardable_version_id

  before_versioned do
    @hoardable_operation = hoardable_version&._operation
  end

  after_versioned do
    @hoardable_version_id = hoardable_version&.id
  end

  after_reverted do
    @reverted = true
  end
end

class User < ActiveRecord::Base
  has_many :posts
end

class UserWithTrashedPosts < ActiveRecord::Base
  self.table_name = 'users'
  has_many :posts, -> { unscope(where: [:tableoid]) }, foreign_key: 'user_id'
end

class Current < ActiveSupport::CurrentAttributes
  attribute :user
end

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

  it 'creates a version with previous state' do
    assert_equal post.versions.size, 0
    update_post
    assert_equal post.versions.size, 1
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
    assert_equal post.at(datetime1).title, 'Headline'
    assert_equal post.at(datetime2).title, 'New Headline'
    assert_equal post.at(datetime3).title, 'Revert'
  end

  it 'creates a version that is aware of relationships on parent model' do
    update_post
    version = post.versions.first
    assert_equal version.user, post.user
  end

  it 'tests version is available in callbacks' do
    update_post
    assert_equal post.hoardable_operation, 'update'
    assert post.hoardable_version_id
    assert_nil post.hoardable_version
  end

  it 'tests callbacks not available in version' do
    update_post
    version = post.versions.first
    assert_equal version.send(:hoardable_callbacks_enabled), false
  end

  it 'can be reverted from previous version' do
    attributes = post.attributes.without('updated_at')
    update_post
    version = post.versions.first
    version.revert!
    assert_equal post.attributes.without('updated_at'), attributes
    refute_equal post.updated_at, attributes['updated_at']
  end

  it 'creates a version on deletion and can be reverted' do
    post_id = post.id
    attributes = post.attributes.without('updated_at')
    post.destroy!
    assert_raises(ActiveRecord::RecordNotFound) { post.reload }
    version = PostVersion.last
    assert_equal version.post_id, post_id
    reverted_post = version.revert!
    assert_equal reverted_post.attributes.without('updated_at'), attributes
    refute_equal reverted_post.updated_at, post.updated_at
  end

  it 'can hook into revert callback' do
    assert_nil post.reverted
    post.destroy!
    reverted_post = PostVersion.last.revert!
    refute_nil reverted_post.reverted
  end

  it 'can query for trashed versions' do
    update_post
    assert_equal PostVersion.count, 1
    assert_equal PostVersion.trashed.size, 0
    post.destroy!
    assert_equal PostVersion.count, 2
    assert_equal PostVersion.trashed.size, 1
    version = PostVersion.last
    version.revert!
    assert_equal PostVersion.count, 2
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

  it 'can opt-out of versioning on deletion' do
    Hoardable.with(save_trash: false) do
      update_post
      assert_equal post.versions.size, 1
      post.destroy!
      assert_equal PostVersion.count, 0
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
    assert_equal Post.with_versions.count, 3
    assert_equal Post.versions.count, 1
    post.destroy!
    assert_equal Post.count, 1
    assert_equal Post.with_versions.count, 3
    assert_equal Post.versions.count, 2
  end
end
