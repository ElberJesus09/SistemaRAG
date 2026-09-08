-- Visibilidad de usuarios para el panel.
-- Ejecutar desde Supabase > SQL Editor despues de las migraciones anteriores.
--
-- Motivo: de las nueve tablas del esquema, `profiles` y `feedback` eran las
-- unicas que ningun endpoint exponia. El panel sabia cuantos usuarios habia,
-- pero no quienes eran, ni cuando entraron, ni que preguntaban.
--
-- Sobre "conectados": una API REST sin sesion persistente no puede saber quien
-- esta con la app abierta. Lo que si es observable y honesto son dos cosas:
--   - la ultima vez que cada usuario inicio sesion (auth.users.last_sign_in_at)
--   - la ultima vez que pregunto algo (questions.created_at)
-- "Activo" aqui significa lo segundo dentro de una ventana de minutos.

create index if not exists feedback_question_idx on public.feedback(question_id);

create or replace function public.usuarios_con_actividad(
  minutos_activo integer default 15,
  limite integer default 500
)
returns table (
  id uuid,
  email text,
  full_name text,
  role text,
  is_active boolean,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  preguntas integer,
  ultima_pregunta timestamptz,
  activo boolean,
  votos_positivos integer,
  votos_negativos integer
)
language sql
stable
security definer
set search_path = public, auth
as $$
  with actividad as (
    select
      q.user_id,
      count(*)::int as preguntas,
      max(q.created_at) as ultima_pregunta
    from public.questions q
    where q.user_id is not null
    group by q.user_id
  ),
  votos as (
    select
      f.user_id,
      count(*) filter (where f.rating > 0)::int as positivos,
      count(*) filter (where f.rating < 0)::int as negativos
    from public.feedback f
    group by f.user_id
  )
  select
    p.id,
    u.email::text,
    p.full_name,
    p.role,
    p.is_active,
    p.created_at,
    u.last_sign_in_at,
    coalesce(a.preguntas, 0),
    a.ultima_pregunta,
    a.ultima_pregunta >= now() - make_interval(mins => greatest(minutos_activo, 1)),
    coalesce(v.positivos, 0),
    coalesce(v.negativos, 0)
  from public.profiles p
  left join auth.users u on u.id = p.id
  left join actividad a on a.user_id = p.id
  left join votos v on v.user_id = p.id
  order by a.ultima_pregunta desc nulls last, p.created_at desc
  limit greatest(limite, 1);
$$;

revoke all on function public.usuarios_con_actividad(integer, integer)
  from public, anon, authenticated;
grant execute on function public.usuarios_con_actividad(integer, integer)
  to service_role;

notify pgrst, 'reload schema';
