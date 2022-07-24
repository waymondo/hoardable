# frozen_string_literal: true

class Post < ActiveRecord::Base
  enum :status, { draft: 1, live: 2 }
  include Archiversion::Model
end
