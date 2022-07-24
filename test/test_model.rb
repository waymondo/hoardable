# frozen_string_literal: true

require 'test_helper'

class TestModel < Minitest::Test
  def setup
    ActiveRecord::Schema.define do
      create_table :posts do |t|
        t.text :body
        t.string :title, null: false
        t.integer :status, default: 0
        t.timestamps
      end
    end
    generate_versions_table('posts')
    super
  end

  def teardown
    teardown_db
    super
  end

  def test_that_versions_are_created
    post = Post.create!(title: 'Headline')
    assert_equal Post.count, 1
    assert_equal post.versions.size, 0
    post.versioned_update!(title: 'New Headline', status: 1)
    assert_equal post.versions.size, 1
  end
end
