-- =============================================================================
-- get_participants
--
-- Organizer view of a session: basic session info plus the names of the
-- participants who have joined.
--
-- Authorization: the organizer token must belong to the session (checked
-- against public.organizers, same as publish_session).
--
-- Participants listed:
--   * active = true only
--   * is_organizer = false only, so joinedCount is comparable with
--     maxParticipants (join_session counts capacity the same way)
--   * sorted by name, case-insensitive (public.normalize_participant_name),
--     then by the stored name and id so the order is stable
--
-- Never returned: assigned_color_id, target_color_id, browser_token,
-- recovery_code, organizer tokens, invite code, or any gift assignment.
--
-- Read-only: no rows are written or locked.
--
-- Parameters are copied into local variables through function-qualified
-- references, and only those variables are used in SQL.
--
-- Custom SQLSTATEs (mapped to HTTP codes by the get-participants Edge Function):
--   GP001 -> session not found                         (404)
--   GP002 -> organizer token does not match session    (403)
--   GP003 -> invalid input                             (422)
-- =============================================================================

create or replace function public.get_participants(
  p_session_id      uuid,
  p_organizer_token text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_session_id      uuid := get_participants.p_session_id;
  v_organizer_token text := get_participants.p_organizer_token;
  v_session         record;
  v_participants    jsonb;
  v_joined_count    integer;
begin
  -- ---------------------------------------------------------------------------
  -- Argument checks
  -- ---------------------------------------------------------------------------
  if v_session_id is null then
    raise exception 'sessionId is required' using errcode = 'GP003';
  end if;

  if v_organizer_token is null or btrim(v_organizer_token) = '' then
    raise exception 'organizerToken is required' using errcode = 'GP003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Session lookup
  -- ---------------------------------------------------------------------------
  select s.id, s.session_name, s.status, s.published, s.max_participants
    into v_session
    from public.sessions s
   where s.id = v_session_id;

  if not found then
    raise exception 'Session not found' using errcode = 'GP001';
  end if;

  -- ---------------------------------------------------------------------------
  -- Authorize: the organizer token must belong to this session
  -- ---------------------------------------------------------------------------
  if not exists (
    select 1
      from public.organizers o
     where o.session_id = v_session_id
       and o.organizer_token = v_organizer_token
  ) then
    raise exception 'Organizer token is not valid for this session' using errcode = 'GP002';
  end if;

  -- ---------------------------------------------------------------------------
  -- Participants (whitelisted fields only)
  -- ---------------------------------------------------------------------------
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'participantId',   p.id,
               'participantName', p.participant_name
             )
             order by public.normalize_participant_name(p.participant_name),
                      p.participant_name,
                      p.id
           ),
           '[]'::jsonb
         ),
         count(*)
    into v_participants, v_joined_count
    from public.participants p
   where p.session_id = v_session_id
     and p.active = true
     and p.is_organizer = false;

  -- ---------------------------------------------------------------------------
  -- Result
  -- ---------------------------------------------------------------------------
  return jsonb_build_object(
    'sessionId',       v_session.id,
    'sessionName',     v_session.session_name,
    'status',          v_session.status,
    'published',       v_session.published,
    'joinedCount',     v_joined_count,
    'maxParticipants', v_session.max_participants,
    'participants',    v_participants
  );
end;
$$;

-- Only the service role (ctx.supabaseAdmin) may call this function.
revoke all on function public.get_participants(uuid, text)
  from public, anon, authenticated;
grant execute on function public.get_participants(uuid, text)
  to service_role;
