# frozen_string_literal: true

ActiveRecord::Base.establish_connection(
  adapter: 'postgresql',
  database: 'hoardable',
  host: 'localhost',
  port: nil,
  username: ENV.fetch('POSTGRES_USER', nil),
  password: ENV.fetch('POSTGRES_PASSWORD', nil)
)

ActiveRecord::Schema.verbose = false
# ActiveRecord::Base.logger = Logger.new($stdout)

def truncate_db
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.execute("TRUNCATE #{table} RESTART IDENTITY")
  end
end

ActiveRecord::Base.connection.tables.each do |table|
  next unless ActiveRecord::Base.connection.table_exists?(table)

  ActiveRecord::Base.connection.drop_table(table, force: :cascade)
end

ActiveRecord::Schema.define do
  create_table :posts do |t|
    t.text :body
    t.string :title, null: false
    t.string :status, default: 'draft'
    t.bigint :user_id, null: false, index: true
    t.timestamps
  end

  create_table :libraries, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
    t.string :name, null: false
    t.timestamps
  end

  create_table :books, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
    t.string :title, null: false
    t.uuid :library_id, null: false, index: true
    t.timestamps
  end

  create_table :comments do |t|
    t.text :body
    t.bigint :post_id, null: false, index: true
    t.timestamps
  end

  create_table :likes do |t|
    t.bigint :comment_id, null: false, index: true
    t.timestamps
  end

  create_table :users do |t|
    t.string :name, null: false
    t.timestamps
  end

  create_table :bookmarks do |t|
    t.string :name, null: false
  end
end

def generate_versions_table(table_name)
  Rails::Generators.invoke('hoardable:migration', [table_name, '--quiet'], destination_root: tmp_dir)
  Dir[File.join(tmp_dir, 'db/migrate/*.rb')].sort.each { |file| require file }
  "Create#{table_name.classify.singularize}Versions".constantize.migrate(:up)
end

generate_versions_table('Post')
generate_versions_table('Comment')
generate_versions_table('Book')
generate_versions_table('Library')
generate_versions_table('Bookmark')
generate_versions_table('Like')
