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
    empty_tmp_dir
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

  after do
    teardown_db
  end

  let(:user) do
    User.create!(name: 'Justin')
  end

  let(:post) do
    Post.create!(title: 'Headline', user: user)
  end

  def update_post(attributes = { title: 'New Headline', status: :live })
    post.versioned_update!(attributes)
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
end
