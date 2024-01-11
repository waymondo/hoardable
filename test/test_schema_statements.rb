# frozen_string_literal: true

require "helper"

class TestSchemaStatements < ActiveSupport::TestCase
  test "it dumps table inheritance options to schema.rb" do
    output = dump_table_schema("post_versions")
    assert_match(<<~SCHEMA.squish, output)
      create_table \"post_versions\",
      id: :bigint,
      default: -> { \"nextval('posts_id_seq'::regclass)\" },
      options: \"INHERITS (posts)\"
    SCHEMA
  end

  test "it does not dump table inheritance options for non inherited table" do
    output = dump_table_schema("posts")
    assert_no_match("options: \"INHERITS", output)
  end

  private def dump_table_schema(table_name)
    connection = ActiveRecord::Base.connection
    ActiveRecord::SchemaDumper.ignore_tables = connection.data_sources - [table_name]
    stream = StringIO.new
    output = ActiveRecord::SchemaDumper.dump(connection, stream).string
  end
end
