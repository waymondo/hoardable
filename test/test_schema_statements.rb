# frozen_string_literal: true

require "helper"

class TestSchemaStatements < ActiveSupport::TestCase
  test "it dumps table inheritance options to schema.rb" do
    connection = ActiveRecord::Base.connection
    ActiveRecord::SchemaDumper.ignore_tables = connection.data_sources - ["post_versions"]
    stream = StringIO.new
    output = ActiveRecord::SchemaDumper.dump(connection, stream).string
    assert_match(<<~SCHEMA.squish, output)
      create_table \"post_versions\",
      id: :bigint,
      default: -> { \"nextval('posts_id_seq'::regclass)\" },
      options: \"INHERITS (posts)\"
    SCHEMA
  end
end
