CREATE OR REPLACE FUNCTION <%= function_name %>() RETURNS trigger
  LANGUAGE plpgsql AS
$$
BEGIN
  NEW.hoardable_id = NEW.<%= primary_key %>;
  RETURN NEW;
END;$$;
