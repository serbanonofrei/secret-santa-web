-- =============================================================================
-- create_session_with_colors
--
-- Creates everything for a new session in ONE transaction (a PL/pgSQL function
-- body runs atomically; any RAISE rolls back every insert made so far):
--   1. public.sessions               (status = 'DRAFT', published = false)
--   2. public.organizers             (organizer token)
--   3. public.session_color_options  (all allowed colors)
--   4. public.colors                 (randomly selected colors,
--                                     target_color_id = NULL, assigned = false)
--
-- Called by the `create-session` Edge Function via supabaseAdmin.rpc(...).
-- The random choices (invite code, token, selected colors) are made in the Edge
-- Function. This function re-checks the invariants anyway as a second line of
-- defence.
--
-- Custom SQLSTATEs (mapped to HTTP codes by the Edge Function):
--   SC001 -> one or more allowed or selected color ids do not exist in
--            public.color_catalog or are not enabled (enabled = false)
--   SC002 -> invalid arguments (bad counts, duplicates, selection not in allowed set)
--
-- Invite code uniqueness is enforced by the existing constraint
-- public.sessions.sessions_invite_code_key; a collision raises 23505 and the
-- Edge Function retries with a new code.
-- =============================================================================

create or replace function public.create_session_with_colors(
  p_session_name       text,
  p_invite_code        text,
  p_max_participants   integer,
  p_organizer_token    text,
  p_allowed_color_ids  integer[],
  p_selected_color_ids integer[]
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session_id uuid;
  v_missing    integer[];
  v_selected   jsonb;
begin
  -- ---------------------------------------------------------------------------
  -- Defensive argument checks
  -- ---------------------------------------------------------------------------
  if p_session_name is null
     or char_length(btrim(p_session_name)) not between 3 and 100 then
    raise exception 'sessionName must be between 3 and 100 characters'
      using errcode = 'SC002';
  end if;

  if p_max_participants is null or p_max_participants not between 2 and 100 then
    raise exception 'maxParticipants must be between 2 and 100'
      using errcode = 'SC002';
  end if;

  if p_allowed_color_ids is null
     or cardinality(p_allowed_color_ids) < p_max_participants then
    raise exception 'allowedColors count must be >= maxParticipants'
      using errcode = 'SC002';
  end if;

  if cardinality(p_allowed_color_ids)
     <> (select count(distinct a.id) from unnest(p_allowed_color_ids) as a(id)) then
    raise exception 'allowedColors must not contain duplicates'
      using errcode = 'SC002';
  end if;

  if p_selected_color_ids is null
     or cardinality(p_selected_color_ids) <> p_max_participants
     or cardinality(p_selected_color_ids)
        <> (select count(distinct s.id) from unnest(p_selected_color_ids) as s(id))
     or not (p_selected_color_ids <@ p_allowed_color_ids) then
    raise exception 'selected colors must be % distinct values taken from allowedColors',
      p_max_participants
      using errcode = 'SC002';
  end if;

  -- ---------------------------------------------------------------------------
  -- All allowed AND selected colors must exist in the catalog AND be enabled.
  -- FOR SHARE locks the matching catalog rows until commit so a concurrent
  -- transaction cannot disable/delete them between these checks and the inserts.
  -- ---------------------------------------------------------------------------
  perform 1
     from public.color_catalog c
    where c.id = any(p_allowed_color_ids || p_selected_color_ids)
      and c.enabled = true
      for share;

  select coalesce(array_agg(a.id order by a.id), '{}'::integer[])
    into v_missing
    from unnest(p_allowed_color_ids) as a(id)
   where not exists (
           select 1
             from public.color_catalog c
            where c.id = a.id
              and c.enabled = true
         );

  if cardinality(v_missing) > 0 then
    raise exception 'Unknown or disabled color catalog ids: %', array_to_string(v_missing, ', ')
      using errcode = 'SC001',
            detail  = array_to_string(v_missing, ',');
  end if;

  -- Selected colors: checked explicitly rather than relying on the
  -- "selected <@ allowed" subset rule above, so this function never inserts a
  -- disabled color into public.colors even if that rule changes.
  select coalesce(array_agg(s.id order by s.id), '{}'::integer[])
    into v_missing
    from unnest(p_selected_color_ids) as s(id)
   where not exists (
           select 1
             from public.color_catalog c
            where c.id = s.id
              and c.enabled = true
         );

  if cardinality(v_missing) > 0 then
    raise exception 'Unknown or disabled selected color catalog ids: %', array_to_string(v_missing, ', ')
      using errcode = 'SC001',
            detail  = array_to_string(v_missing, ',');
  end if;

  -- ---------------------------------------------------------------------------
  -- 1. Session
  -- ---------------------------------------------------------------------------
  insert into public.sessions (session_name, invite_code, max_participants, status, published)
  values (btrim(p_session_name), p_invite_code, p_max_participants, 'DRAFT', false)
  returning id into v_session_id;

  -- ---------------------------------------------------------------------------
  -- 2. Organizer
  -- ---------------------------------------------------------------------------
  insert into public.organizers (session_id, organizer_token)
  values (v_session_id, p_organizer_token);

  -- ---------------------------------------------------------------------------
  -- 3. Allowed colors
  -- ---------------------------------------------------------------------------
  insert into public.session_color_options (session_id, color_catalog_id)
  select v_session_id, a.id
    from unnest(p_allowed_color_ids) as a(id);

  -- ---------------------------------------------------------------------------
  -- 4. Selected colors: no Secret Santa chain yet
  -- ---------------------------------------------------------------------------
  insert into public.colors (session_id, color_catalog_id, target_color_id, assigned)
  select v_session_id, s.id, null, false
    from unnest(p_selected_color_ids) with ordinality as s(id, ord)
   order by s.ord;

  -- ---------------------------------------------------------------------------
  -- Result
  -- ---------------------------------------------------------------------------
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'catalogId', c.id,
               'name',      c.color_name,
               'hexColor',  c.hex_color
             )
             order by s.ord
           ),
           '[]'::jsonb
         )
    into v_selected
    from unnest(p_selected_color_ids) with ordinality as s(id, ord)
    join public.color_catalog c on c.id = s.id;

  return jsonb_build_object(
    'sessionId',      v_session_id,
    'selectedColors', v_selected
  );
end;
$$;

-- Only the service role (ctx.supabaseAdmin) may call this function.
revoke all on function public.create_session_with_colors(text, text, integer, text, integer[], integer[])
  from public, anon, authenticated;
grant execute on function public.create_session_with_colors(text, text, integer, text, integer[], integer[])
  to service_role;
