-- Define 'role' type with values 'user' and 'admin'
CREATE TYPE public.role AS ENUM ('user', 'admin');

-- Create users table
CREATE TABLE public.users (
    id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    email text NULL,
    role public.role NULL DEFAULT 'user'::role,
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users (id) ON UPDATE CASCADE ON DELETE CASCADE
) TABLESPACE pg_default;

-- Define sync_users function
CREATE OR REPLACE FUNCTION sync_users () RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, created_at)
  SELECT NEW.id, NEW.created_at;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for sync_users
CREATE TRIGGER sync_users_trigger
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION sync_users();

-- Define initialize_user_meta_data function
CREATE OR REPLACE FUNCTION initialize_user_meta_data()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IS NULL THEN
        RAISE EXCEPTION 'This function can only be called from a trigger.';
    END IF;

    UPDATE auth.users
    SET raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', NEW.role)
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for initialize_user_meta_data
CREATE TRIGGER initialize_user_meta_data_trigger
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION initialize_user_meta_data();

-- Define update_user_meta_data function
CREATE OR REPLACE FUNCTION update_user_meta_data () RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP IS NULL THEN
        RAISE EXCEPTION 'This function can only be called from a trigger.';
    END IF;

    IF (NEW.role IS DISTINCT FROM OLD.role) THEN
        UPDATE auth.users
        SET raw_app_meta_data = jsonb_set(coalesce(raw_app_meta_data, '{}'::jsonb), '{role}', to_jsonb(NEW.role))
        WHERE id = NEW.id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_user_meta_data_trigger
AFTER UPDATE OF role ON public.users
FOR EACH ROW
WHEN (OLD.role IS DISTINCT FROM NEW.role)
EXECUTE FUNCTION update_user_meta_data();

-- Alter the security definition of the update_user_meta_data function
ALTER FUNCTION update_user_meta_data() SECURITY DEFINER;
