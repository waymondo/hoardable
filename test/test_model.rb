# frozen_string_literal: true

require 'test_helper'

class Post < ActiveRecord::Base
  include Archiversion::Model
  enum :status, { draft: 0, live: 1 }
end

class TestModel < Minitest::Test
  extend Minitest::Spec::DSL

  before do
    ActiveRecord::Schema.define do
      create_table :posts do |t|
        t.text :body
        t.string :title, null: false
        t.integer :status, default: 0
        t.timestamps
      end
    end
    generate_versions_table('posts')
  end

  after do
    teardown_db
  end

  let(:post) { Post.create!(title: 'Headline') }

  def test_that_versions_are_created
    assert_equal post.versions.size, 0
    post.versioned_update!(title: 'New Headline', status: :live)
    assert_equal post.status, 'live'
    assert_equal post.title, 'New Headline'
    assert_equal post.versions.size, 1
    version = post.versions.first
    assert_equal version.status, 'draft'
    assert_equal version.title, 'Headline'
  end

  def test_versions_are_read_only_and_do_not_have_versions
    post.versioned_update!(title: 'New Headline', status: :live)
    version = post.versions.first
    assert_raises(ActiveRecord::ReadOnlyRecord) { version.update!(title: 'Rewriting History') }
    assert_raises(ActiveRecord::AssociationNotFoundError) { version.destroy! }
    assert_raises(ActiveRecord::AssociationNotFoundError) { version.versions }
  end
end
