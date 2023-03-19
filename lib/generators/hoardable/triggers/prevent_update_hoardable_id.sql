CREATE TRIGGER <%= table_name %>_prevent_update_hoardable_id
  BEFORE UPDATE ON <%= table_name %> FOR EACH ROW
  EXECUTE PROCEDURE hoardable_prevent_update_id();
