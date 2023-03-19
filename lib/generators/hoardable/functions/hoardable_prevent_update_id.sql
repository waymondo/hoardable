CREATE OR REPLACE FUNCTION hoardable_prevent_update_id() RETURNS trigger
  LANGUAGE plpgsql AS
$$BEGIN
  IF NEW.hoardable_id <> OLD.hoardable_id THEN
    RAISE EXCEPTION 'hoardable id cannot be updated';
  END IF;
  RETURN NEW;
END;$$;
