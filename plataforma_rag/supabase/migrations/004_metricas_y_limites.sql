-- Agregacion de metricas dentro de Postgres.
-- Ejecutar desde Supabase > SQL Editor despues de las migraciones anteriores.
--
-- Motivo: `analytics_service.resumen()` traia hasta 10 000 filas de `questions`
-- a Python en cada carga del panel y las agregaba en memoria. Con estas
-- funciones el trabajo lo hace la base y viaja solo el resultado.

create index if not exists questions_user_created_idx
  on public.questions(user_id, created_at desc);

-- Indicadores del periodo -----------------------------------------------------
create or replace function public.metricas_resumen(dias integer default 30)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with periodo as (
    select *
    from public.questions
    where created_at >= now() - make_interval(days => greatest(dias, 1))
  ),
  indicadores as (
    select
      count(*)::int as preguntas,
      count(*) filter (where status = 'answered')::int as respondidas,
      coalesce(round(avg(latency_ms))::int, 0) as demora_media,
      coalesce(
        round(percentile_cont(0.95) within group (order by latency_ms))::int, 0
      ) as demora_p95,
      -- Medianas del desglose: responden "a donde se va el tiempo".
      coalesce(round(percentile_cont(0.5) within group (order by latency_ms))::int, 0)
        as total_p50,
      coalesce(round(percentile_cont(0.5) within group (order by retrieval_ms))::int, 0)
        as busqueda_p50,
      coalesce(round(percentile_cont(0.5) within group (order by generation_ms))::int, 0)
        as generacion_p50
    from periodo
  ),
  por_dia as (
    select
      to_char(date_trunc('day', created_at), 'YYYY-MM-DD') as dia,
      count(*)::int as preguntas,
      coalesce(round(avg(latency_ms))::int, 0) as demora_media
    from periodo
    group by 1
    order by 1
  ),
  recurrentes as (
    select
      (array_agg(question order by created_at desc))[1] as question,
      count(*)::int as veces
    from periodo
    where normalized_question <> ''
    group by normalized_question
    order by count(*) desc, max(created_at) desc
    limit 10
  ),
  recientes as (
    select
      id, user_id, question, status, latency_ms, retrieval_ms, generation_ms,
      top_similarity, created_at
    from periodo
    order by created_at desc
    limit 20
  )
  select jsonb_build_object(
    'period_days', greatest(dias, 1),
    'kpis', jsonb_build_object(
      'questions', (select preguntas from indicadores),
      'answer_rate', case
        when (select preguntas from indicadores) = 0 then 0
        else round(
          (select respondidas from indicadores)::numeric * 100
          / (select preguntas from indicadores), 1)
      end,
      'average_latency_ms', (select demora_media from indicadores),
      'p95_latency_ms', (select demora_p95 from indicadores),
      'users', (select count(*)::int from public.profiles),
      'documents', (select count(*)::int from public.documents where status = 'active'),
      'open_alerts', (select count(*)::int from public.alerts where status = 'open')
    ),
    'timing', jsonb_build_object(
      'total_p50', (select total_p50 from indicadores),
      'retrieval_p50', (select busqueda_p50 from indicadores),
      'generation_p50', (select generacion_p50 from indicadores),
      'other_p50', greatest(
        (select total_p50 - busqueda_p50 - generacion_p50 from indicadores), 0)
    ),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object(
        'date', dia, 'questions', preguntas, 'average_latency_ms', demora_media))
      from por_dia), '[]'::jsonb),
    'recurrent_questions', coalesce((
      select jsonb_agg(jsonb_build_object('question', question, 'count', veces))
      from recurrentes), '[]'::jsonb),
    'recent_questions', coalesce((
      select jsonb_agg(to_jsonb(recientes)) from recientes), '[]'::jsonb)
  );
$$;

revoke all on function public.metricas_resumen(integer) from public, anon, authenticated;
grant execute on function public.metricas_resumen(integer) to service_role;

notify pgrst, 'reload schema';
