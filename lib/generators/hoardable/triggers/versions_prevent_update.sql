CREATE TRIGGER <%= singularized_table_name %>_versions_prevent_update
  BEFORE UPDATE ON <%= singularized_table_name %>_versions FOR EACH ROW
  EXECUTE PROCEDURE hoardable_version_prevent_update();
