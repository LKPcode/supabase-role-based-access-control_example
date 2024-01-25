
# User Management and Role-Based Access Control in Supabase/PostgreSQL

This README documents a PostgreSQL script designed for automatic synchronization of user data and implementation of Role-Based Access Control (RBAC) in a database, particularly suitable for Supabase environments. The script includes the creation of a custom role type, a users table, and various functions and triggers to manage user data and roles.

This repository is a bit too complicated for my usecase. [supabase-custom-claims](https://github.com/supabase-community/supabase-custom-claims)


# PostgreSQL Database Script for User Management in Supabase Environment

This script is designed for use with a PostgreSQL database, particularly in a Supabase environment. It facilitates automatic data synchronization and Role-Based Access Control (RBAC) implementation for user management.

- **Define 'role' type with values 'user' and 'admin':**
  - Custom enumerated type used to specify user roles within the database.

- **Create users table:**
  - Stores essential user information including a unique ID, creation timestamp, email, and role.
  - Has a foreign key relationship with the 'auth.users' table, ensuring referential integrity.

- **Define sync_users function:**
  - A PL/pgSQL function acting as a trigger function.
  - Automatically inserts new records into the 'public.users' table after a new row is added to 'auth.users'.

- **Create trigger for sync_users:**
  - Ensures that any new insertion in the 'auth.users' table is reflected in the 'public.users' table.

- **Define initialize_user_meta_data function:**
  - A trigger function that initializes user metadata.
  - Updates the 'raw_app_meta_data' JSONB field in 'auth.users' with the user's role upon insertion into 'public.users'.

- **Create trigger for initialize_user_meta_data:**
  - Activated after a new insert in 'public.users', executing the initialize_user_meta_data function.

- **Define update_user_meta_data function:**
  - Updates user metadata specifically when there is a change in the user's role.

- **Alter the security definition of update_user_meta_data:**
  - By setting the function as SECURITY DEFINER, it executes with the privileges of the user who defined the function.
  - Crucial for preventing unauthorized changes and ensuring role updates are included in the JWT for RBAC.

**Note**: The implementation of SECURITY DEFINER is essential for these functions to operate without encountering an Unauthorized change error. This script helps in managing user roles effectively and securely, ensuring that role changes are accurately reflected in JWTs for authenticated sessions.


## Custom Type: `role`

The script starts by defining a custom enumerated type named `role`, which includes two roles: 'user' and 'admin'. This type is used to specify the role of users in the database.

```sql
CREATE TYPE public.role AS ENUM ('user', 'admin');
```

## Table: `public.users`

A `users` table is created in the public schema to store user data. This table includes fields for a unique ID, creation timestamp, email, and role. It also establishes a foreign key relationship with the `auth.users` table.

```sql
CREATE TABLE public.users (
    id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    email text NULL,
    role public.role NULL DEFAULT 'user'::role,
    CONSTRAINT users_pkey PRIMARY KEY (id),
    CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users (id) ON UPDATE CASCADE ON DELETE CASCADE
) TABLESPACE pg_default;
```

## Function: `sync_users`

This PL/pgSQL function, `sync_users`, is designed to be triggered after an insert operation on the `auth.users` table. It automatically inserts new user records into the `public.users` table.

```sql
CREATE OR REPLACE FUNCTION sync_users () RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, created_at)
  SELECT NEW.id, NEW.created_at;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

## Trigger: `sync_users_trigger`

The `sync_users_trigger` is an AFTER INSERT trigger on the `auth.users` table. It executes the `sync_users` function for each row inserted into `auth.users`.

```sql
CREATE TRIGGER sync_users_trigger
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION sync_users();
```

## Function: `initialize_user_meta_data`

The `initialize_user_meta_data` function is intended to be used as a trigger function on the `public.users` table. It updates the `raw_app_meta_data` JSONB field in `auth.users` with the role of the newly inserted user.

```sql
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
```

## Trigger: `initialize_user_meta_data_trigger`

This AFTER INSERT trigger on the `public.users` table executes the `initialize_user_meta_data` function for each new row, thereby initializing metadata for new users.

```sql
CREATE TRIGGER initialize_user_meta_data_trigger
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION initialize_user_meta_data();
```

## Function: `update_user_meta_data`

The `update_user_meta_data` function updates the user's role in the `raw_app_meta_data` JSONB field in `auth.users` if there's a change in the `public.users.role` column.

```sql
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
```

## Alter Function: Security Definition

This alteration to the `update_user_meta_data` function sets it to execute with the privileges of the user who defined the function (SECURITY DEFINER), which is essential for performing operations that require higher privileges and to avoid unauthorized change errors.

```sql
ALTER FUNCTION update_user_meta_data() SECURITY DEFINER;
```

## Trigger `update_user_meta_data_trigger`

```sql
CREATE TRIGGER update_user_meta_data_trigger
AFTER UPDATE OF role ON public.users
FOR EACH ROW
WHEN (OLD.role IS DISTINCT FROM NEW.role)
EXECUTE FUNCTION update_user_meta_data();
```

## Conclusion

This script facilitates the effective management of user roles in a PostgreSQL database, ensuring that user role changes are accurately reflected and included in JWTs for authenticated sessions in Supabase environments.



## Delete functions and triggers

```sql
-- Dropping Triggers
DROP TRIGGER IF EXISTS sync_users_trigger ON auth.users;
DROP TRIGGER IF EXISTS initialize_user_meta_data_trigger ON public.users;

-- Dropping Functions
DROP FUNCTION IF EXISTS sync_users();
DROP FUNCTION IF EXISTS initialize_user_meta_data();
DROP FUNCTION IF EXISTS update_user_meta_data();
```
