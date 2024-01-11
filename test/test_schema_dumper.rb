# frozen_string_literal: true

require "helper"

class TestSchemaDumper < ActiveSupport::TestCase
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
    assert_match("create_table \"posts\", force: :cascade do |t|\n", output)
  end

  test "it dumps inherited table after parent table, and trigger after both" do
    output = dump_table_schema("post_versions", "posts")
    assert posts_index = output.index(/create_table "posts"/)
    assert post_versions_index = output.index(/create_table "post_versions"/)
    assert(
      post_versions_trigger_index = output.index(/create_trigger :post_versions_prevent_update/)
    )
    assert post_versions_index > posts_index
    assert post_versions_trigger_index > post_versions_index
  end

  private def dump_table_schema(*table_names)
    connection = ActiveRecord::Base.connection
    ActiveRecord::SchemaDumper.ignore_tables = connection.data_sources - table_names
    stream = StringIO.new
    ActiveRecord::SchemaDumper.dump(connection, stream).string
  end
end
