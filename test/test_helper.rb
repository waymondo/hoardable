# frozen_string_literal: true

require 'bundler/setup'
require 'debug'
require 'active_support/concern'
require 'active_record'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'hoardable'

require 'minitest/autorun'
require 'minitest/spec'

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

def tmp_dir
  File.expand_path('../tmp', __dir__)
end

FileUtils.rm_f Dir.glob("#{tmp_dir}/**/*")

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

  create_table :comments do |t|
    t.text :body
    t.bigint :post_id, null: false, index: true
    t.timestamps
  end

  create_table :users do |t|
    t.string :name, null: false
    t.timestamps
  end
end

def generate_versions_table(table_name)
  Rails::Generators.invoke('hoardable:migration', [table_name, '--quiet'], destination_root: tmp_dir)
  Dir[File.join(tmp_dir, 'db/migrate/*.rb')].sort.each { |file| require file }
  "Create#{table_name.classify.singularize}Versions".constantize.migrate(:up)
end

generate_versions_table('posts')
generate_versions_table('comments')
