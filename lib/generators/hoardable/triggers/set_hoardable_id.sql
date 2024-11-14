CREATE TRIGGER <%= table_name %>_set_hoardable_id
  BEFORE INSERT ON <%= table_name %> FOR EACH ROW
  EXECUTE PROCEDURE <%= function_name %>();
