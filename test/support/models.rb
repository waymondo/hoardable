# frozen_string_literal: true

class Post < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :user
  has_many :comments, dependent: :destroy, hoardable: true
  has_many :likes, through: :comments, hoardable: true
  attr_reader :_hoardable_operation, :reverted, :untrashed, :hoardable_version_id

  after_versioned { @hoardable_version_id = hoardable_version&.id }

  after_untrashed do
    @untrashed = true
    CommentVersion.trashed.with_hoardable_event_uuid(hoardable_event_uuid).find_each(&:untrash!)
  end

  after_reverted { @reverted = true }
end

module Hoardable
  class Post < ::ActiveRecord::Base
    include Hoardable::Model
    self.table_name = "posts"
    belongs_to :user
  end
end

class UnversionedPost < ::ActiveRecord::Base
  include Hoardable::Model
  self.table_name = "posts"
  belongs_to :user
  hoardable_config version_updates: false
end

class UnversionablePost < ActiveRecord::Base
  include Hoardable::Model
  self.table_name = "posts"
  belongs_to :user

  after_versioned { raise StandardError, "readonly" }
end

class PostWithRichText < ActiveRecord::Base
  include Hoardable::Model
  self.table_name = "posts"
  belongs_to :user
  has_rich_text :content, hoardable: true
  has_rich_text :description, hoardable: true
end

class PostWithEncryptedRichText < ActiveRecord::Base
  include Hoardable::Model
  self.table_name = "posts"
  belongs_to :user
  has_rich_text :content, encrypted: true, hoardable: true
end

class PostWithUnhoardableRichText < ActiveRecord::Base
  include Hoardable::Model
  self.table_name = "posts"
  belongs_to :user
  has_rich_text :content
end

class User < ActiveRecord::Base
  include Hoardable::Model
  has_many :posts, hoardable: true
  has_one :profile, hoardable: true
  has_rich_text :bio, hoardable: true
  serialize :preferences, coder: JSON
end

class Profile < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :user
  has_hoardable_rich_text :life_story
  has_hoardable_rich_text :diary, encrypted: true
end

class Comment < ActiveRecord::Base
  include Hoardable::Model
  has_many :likes, hoardable: true, dependent: :destroy
  belongs_to :post, trashable: true
end

class Like < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :comment
end

class UserWithTrashedPosts < ActiveRecord::Base
  self.table_name = "users"
  has_many :posts, -> { include_versions }, foreign_key: "user_id"

  has_one :bio, class_name: "Profile", foreign_key: "user_id"
end

class Current < ActiveSupport::CurrentAttributes
  attribute :user
end

class Book < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :library
end

class Masterpiece < Book
  include Hoardable::Model

  def title
    "#{super}!"
  end
end

class Tag < ActiveRecord::Base
  include Hoardable::Model
  self.primary_key = "primary_id"
end

class Library < ActiveRecord::Base
  include Hoardable::Model
  has_many :books, dependent: :destroy
  hoardable_config save_trash: false
end

class Bookmark < ActiveRecord::Base
  include Hoardable::Model
end
