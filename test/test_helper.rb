# frozen_string_literal: true

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

def generate_versions_table(table_name)
  destination_root = File.expand_path('../../tmp', __dir__)
  Rails::Generators.invoke('hoardable:migration', [table_name, '--quiet'], destination_root: destination_root)
  Dir[File.join(destination_root, 'db/migrate/*.rb')].sort.each { |file| require file }
  "Create#{table_name.classify.singularize}Versions".constantize.migrate(:up)
end

def teardown_db
  ActiveRecord::Base.connection.tables.each do |table|
    next unless ActiveRecord::Base.connection.table_exists?(table)

    ActiveRecord::Base.connection.drop_table(table, force: :cascade)
  end
end

def empty_tmp_dir
  FileUtils.rm_f Dir.glob('../tmp/**/*')
end

empty_tmp_dir
teardown_db
