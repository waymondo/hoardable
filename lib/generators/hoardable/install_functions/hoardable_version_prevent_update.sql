CREATE OR REPLACE FUNCTION hoardable_version_prevent_update() RETURNS trigger
  LANGUAGE plpgsql AS
$$BEGIN
  RAISE EXCEPTION 'updating a version is not allowed';
  RETURN NEW;
END;$$;
