# frozen_string_literal: true

require 'test_helper'

class Post < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :user
  enum :status, { draft: 0, live: 1 }
end

class User < ActiveRecord::Base
  has_many :posts
end

class TestModel < Minitest::Test
  extend Minitest::Spec::DSL

  before do
    ActiveRecord::Schema.define do
      create_table :posts do |t|
        t.text :body
        t.string :title, null: false
        t.integer :status, default: 0
        t.bigint :user_id, null: false
        t.timestamps
      end

      create_table :users do |t|
        t.string :name, null: false
        t.timestamps
      end
    end
    generate_versions_table('posts')
  end

  after { teardown_db && empty_tmp_dir }

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

  it 'creates read-only versions that do not themselves have versions' do
    update_post
    version = post.versions.first
    assert_raises(ActiveRecord::ReadOnlyRecord) { version.update!(title: 'Rewriting History') }
    assert_raises(ActiveRecord::AssociationNotFoundError) { version.destroy! }
    assert_raises(ActiveRecord::AssociationNotFoundError) { version.versions }
  end

  it 'preserves created_at timestamps, expects during tsrange is set' do
    update_post
    version = post.versions.first
    assert_equal post.created_at, version.created_at
    assert version.hoardable_during
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

  it 'tests callback' do
    Post.class_eval do
      attr_reader :version_title_changed_in_callback

      before_update do
        @version_title_changed_in_callback = true if hoardable_version.title && hoardable_version.title != title
      end
    end
    assert_nil post.version_title_changed_in_callback
    update_post
    assert_equal post.version_title_changed_in_callback, true
  end

  it 'can be restored from previous version' do
    attributes = post.attributes.without('updated_at')
    update_post
    version = post.versions.first
    version.restore!
    assert_equal post.attributes.without('updated_at'), attributes
    refute_equal post.updated_at, attributes['updated_at']
  end

  it 'creates a version on deletion and can be restored' do
    post_id = post.id
    attributes = post.attributes.without('updated_at')
    post.destroy!
    assert_raises(ActiveRecord::RecordNotFound) { post.reload }
    version = PostVersion.last
    assert_equal version.post_id, post_id
    version.restore!
    restored_post = Post.find(post_id)
    assert_equal restored_post.attributes.without('updated_at'), attributes
    refute_equal restored_post.updated_at, post.updated_at
  end

  it 'does not create version on raised error' do
    assert_raises(ActiveModel::UnknownAttributeError) { update_post(non_existent_attribute: 'wat') }
    assert_equal post.versions.size, 0
    assert_nil post.hoardable_version
  end
end
