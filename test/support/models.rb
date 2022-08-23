# frozen_string_literal: true

class Post < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :user
  has_many :comments, dependent: :destroy
  attr_reader :_hoardable_operation, :reverted, :untrashed, :hoardable_version_id

  before_versioned do
    @_hoardable_operation = hoardable_operation
  end

  after_versioned do
    @hoardable_version_id = hoardable_version&.id
  end

  after_untrashed do
    @untrashed = true
    CommentVersion.trashed.with_hoardable_event_uuid(hoardable_event_uuid).find_each(&:untrash!)
  end

  after_reverted do
    @reverted = true
  end
end

class User < ActiveRecord::Base
  has_many :posts
end

class Comment < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :post, -> { include_versions }
end

class UserWithTrashedPosts < ActiveRecord::Base
  self.table_name = 'users'
  has_many :posts, -> { include_versions }, foreign_key: 'user_id'
end

class Current < ActiveSupport::CurrentAttributes
  attribute :user
end

class Book < ActiveRecord::Base
  include Hoardable::Model
  belongs_to :library
end

class Library < ActiveRecord::Base
  include Hoardable::Model
  has_many :books, dependent: :destroy
  hoardable_config save_trash: false
end
