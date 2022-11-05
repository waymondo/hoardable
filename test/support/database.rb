# frozen_string_literal: true

ActiveRecord::Schema.verbose = false

def enable_sql_log
  ActiveRecord::Base.logger = Logger.new($stdout)
end

def truncate_db
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.execute("TRUNCATE #{table} RESTART IDENTITY CASCADE")
  end
end

ActiveRecord::Base.connection.tables.each do |table|
  next unless ActiveRecord::Base.connection.table_exists?(table)

  ActiveRecord::Base.connection.drop_table(table, force: :cascade)
end

ActiveRecord::Schema.define do
  create_table :posts do |t|
    t.text :body
    t.string :uuid, null: false, default: -> { 'gen_random_uuid()' }
    t.string :title, null: false
    t.virtual :lowercase_title, type: :string, as: 'lower(title)', stored: true if SUPPORTS_VIRTUAL_COLUMNS
    t.string :status, default: 'draft'
    t.bigint :user_id, null: false, index: true
    t.timestamps
  end

  create_table :profiles do |t|
    t.string :email, null: false
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

  create_table :tags, id: false do |t|
    t.string :name
    t.integer :primary_id, null: false, primary_key: true
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
    t.text :preferences, default: '{}'
    t.timestamps
  end

  create_table :bookmarks do |t|
    t.string :name, null: false
  end

  create_table :active_storage_blobs do |t|
    t.string   :key, null: false
    t.string   :filename, null: false
    t.string   :content_type
    t.text     :metadata
    t.string   :service_name, null: false
    t.bigint   :byte_size,    null: false
    t.string   :checksum
    t.datetime :created_at, precision: 6, null: false
    t.index [:key], unique: true
  end

  create_table :active_storage_attachments do |t|
    t.string     :name,     null: false
    t.references :record,   null: false, polymorphic: true, index: false, type: :bigint
    t.references :blob,     null: false, type: :bigint
    t.datetime :created_at, precision: 6, null: false
    t.index(
      %i[record_type record_id name blob_id],
      name: :index_active_storage_attachments_uniqueness,
      unique: true
    )
    t.foreign_key :active_storage_blobs, column: :blob_id
  end

  create_table :active_storage_variant_records do |t|
    t.belongs_to :blob, null: false, index: false, type: :bigint
    t.string :variation_digest, null: false
    t.index %i[blob_id variation_digest], name: :index_active_storage_variant_records_uniqueness, unique: true
    t.foreign_key :active_storage_blobs, column: :blob_id
  end

  create_table :action_text_rich_texts do |t|
    t.string :name, null: false
    t.text       :body, size: :long
    t.references :record, null: false, polymorphic: true, index: false, type: :bigint

    t.timestamps

    t.index %i[record_type record_id name], name: 'index_action_text_rich_texts_uniqueness', unique: true
  end
end

def generate_versions_table(table_name)
  Rails::Generators.invoke('hoardable:migration', [table_name, '--quiet'], destination_root: tmp_dir)
  Dir[File.join(tmp_dir, 'db/migrate/*.rb')].sort.each { |file| require file }
  "Create#{table_name.delete(':').singularize}Versions".constantize.migrate(:up)
end

def run_install_migration
  Rails::Generators.invoke('hoardable:install', ['--quiet'], destination_root: tmp_dir)
  Dir[File.join(tmp_dir, 'db/migrate/*.rb')].sort.each { |file| require file }
  'InstallHoardable'.constantize.migrate(:up)
end

run_install_migration
generate_versions_table('Post')
generate_versions_table('User')
generate_versions_table('Comment')
generate_versions_table('Book')
generate_versions_table('Library')
generate_versions_table('Bookmark')
generate_versions_table('Like')
generate_versions_table('Profile')
generate_versions_table('Tag')
generate_versions_table('ActionText::RichText')

ActiveRecord::Base.descendants.each(&:reset_column_information)
