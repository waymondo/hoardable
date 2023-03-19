CREATE OR REPLACE FUNCTION hoardable_source_set_id() RETURNS trigger
  LANGUAGE plpgsql AS
$$
DECLARE
  _pk information_schema.constraint_column_usage.column_name%TYPE;
  _id _pk%TYPE;
BEGIN
  SELECT c.column_name
    FROM information_schema.table_constraints t
    JOIN information_schema.constraint_column_usage c
    ON c.constraint_name = t.constraint_name
    WHERE c.table_name = TG_TABLE_NAME AND t.constraint_type = 'PRIMARY KEY'
    LIMIT 1
    INTO _pk;
  EXECUTE format('SELECT $1.%I', _pk) INTO _id USING NEW;
  NEW.hoardable_id = _id;
  RETURN NEW;
END;$$;
