-- ============================================================================
-- RECUPERACION MANUAL  ·  Plataforma RAG
-- ============================================================================
-- NO EJECUTES ESTE ARCHIVO ENTERO. Es un catalogo de recetas: copia al SQL
-- Editor de Supabase solo el bloque que necesites.
--
-- No es una migracion, por eso vive fuera de supabase/migrations/.
--
-- Esto existe para dos situaciones y ninguna mas:
--   1. Crear el primer administrador, cuando todavia no hay ninguno.
--   2. Recuperar el acceso, si nadie puede entrar al panel.
--
-- Para el dia a dia usa el panel: Usuarios > Contrasena. Lo que hagas aqui
-- NO queda registrado en audit_logs; nadie sabra quien lo hizo ni cuando.
--
-- Aviso: auth.users es una tabla interna de Supabase. Escribir en ella no
-- esta soportado oficialmente y su esquema puede cambiar sin previo aviso.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. ¿QUIENES HAY?   (solo lectura, seguro de ejecutar)
-- ----------------------------------------------------------------------------
-- Empieza siempre por aqui: te dice con que correo entrar y si esa cuenta
-- sirve para algo (rol, si esta activa, si confirmo el correo).

select
  u.email,
  p.full_name                        as nombre,
  p.role                             as rol,
  p.is_active                        as cuenta_activa,
  (u.email_confirmed_at is not null) as correo_confirmado,
  u.last_sign_in_at                  as ultima_sesion,
  u.created_at                       as registrado
from auth.users u
left join public.profiles p on p.id = u.id
order by u.created_at;


-- ----------------------------------------------------------------------------
-- 2. ¿HAY ALGUN ADMINISTRADOR?   (solo lectura)
-- ----------------------------------------------------------------------------
-- Si esto devuelve cero filas, nadie puede entrar al panel: ve al bloque 3.

select u.email, p.full_name, p.is_active, u.last_sign_in_at
from public.profiles p
join auth.users u on u.id = p.id
where p.role = 'admin'
order by u.last_sign_in_at desc nulls last;


-- ----------------------------------------------------------------------------
-- 3. NOMBRAR ADMINISTRADOR
-- ----------------------------------------------------------------------------
-- Cambia el correo y descomenta. El usuario debe existir ya: registralo antes
-- desde la app o desde POST /api/v1/auth/register.

-- update public.profiles
-- set role = 'admin', is_active = true
-- where id = (select id from auth.users where email = 'TU_CORREO@universidad.edu.pe');


-- ----------------------------------------------------------------------------
-- 4. CAMBIAR UNA CONTRASENA
-- ----------------------------------------------------------------------------
-- El prefijo extensions. es necesario: la migracion 001 instalo pgcrypto en ese
-- esquema y el SQL Editor no siempre lo lleva en el search_path.
-- El coste 10 no es opcional: gen_salt('bf') a secas usa 6 y dejaria a ese
-- usuario con un hash mas debil que el del resto.

-- update auth.users
-- set encrypted_password = extensions.crypt('CambiaEstaClave123', extensions.gen_salt('bf', 10)),
--     updated_at = now()
-- where email = 'TU_CORREO@universidad.edu.pe';


-- ----------------------------------------------------------------------------
-- 5. CERRAR LAS SESIONES ABIERTAS DE ESE USUARIO
-- ----------------------------------------------------------------------------
-- Cambiar el hash NO invalida los refresh_token ya emitidos: quien tuviera la
-- app abierta sigue dentro. Si estas recuperando una cuenta comprometida, esto
-- no es opcional.

-- delete from auth.refresh_tokens
-- where user_id = (select id from auth.users where email = 'TU_CORREO@universidad.edu.pe');
--
-- delete from auth.sessions
-- where user_id = (select id from auth.users where email = 'TU_CORREO@universidad.edu.pe');


-- ----------------------------------------------------------------------------
-- 6. CONFIRMAR EL CORREO A MANO
-- ----------------------------------------------------------------------------
-- Si email_confirmed_at es NULL, la contrasena nueva no le servira de nada:
-- Supabase le seguira negando el acceso.

-- update auth.users
-- set email_confirmed_at = now()
-- where email = 'TU_CORREO@universidad.edu.pe'
--   and email_confirmed_at is null;


-- ----------------------------------------------------------------------------
-- 7. REACTIVAR UNA CUENTA DESACTIVADA
-- ----------------------------------------------------------------------------
-- Desde que is_active se comprueba de verdad en la API, una cuenta con
-- is_active = false recibe 403 aunque la contrasena sea correcta.

-- update public.profiles
-- set is_active = true
-- where id = (select id from auth.users where email = 'TU_CORREO@universidad.edu.pe');


-- ----------------------------------------------------------------------------
-- 8. COMPROBAR QUE QUEDO BIEN   (solo lectura)
-- ----------------------------------------------------------------------------

-- select u.email, p.role, p.is_active,
--        (u.email_confirmed_at is not null) as correo_confirmado,
--        u.updated_at
-- from auth.users u
-- left join public.profiles p on p.id = u.id
-- where u.email = 'TU_CORREO@universidad.edu.pe';
