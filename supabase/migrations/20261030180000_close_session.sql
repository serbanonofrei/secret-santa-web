-- =============================================================================
-- close_session
--
-- Closes an ACTIVE session in ONE transaction:
--   1. Locks the session row FOR UPDATE (serializes with concurrent close and
--      join attempts: a join waiting on the lock sees status = 'CLOSED' and is
--      rejected).
--   2. Verifies the organizer token belongs to the session.
--   3. Verifies the session is ACTIVE.
--   4. Sets status = 'CLOSED'. published / draft are left unchanged.
--
-- Participants, colors and the Secret Santa chain are NOT modified.
--
-- Behaviour of the other functions after closure:
--   * join_session        rejects (status <> 'ACTIVE' -> SJ002, HTTP 409). Unchanged.
--   * get_participants    has no status check, keeps working. Unchanged.
--   * get_my_assignment   previously required ACTIVE; redefined below to
--                         accept ACTIVE or CLOSED.
--   * recover_assignment  previously required ACTIVE; redefined below to
--                         accept ACTIVE or CLOSED.
--
-- Custom SQLSTATEs (mapped to HTTP codes by the close-session Edge Function):
--   CS001 -> session not found                                  (404)
--   CS002 -> organizer token does not match session             (403)
--   CS003 -> invalid input                                      (422)
--   CS004 -> session already closed                             (409)
--   CS005 -> session is not ACTIVE (e.g. still DRAFT)           (409)
-- =============================================================================

create or replace function public.close_session(
  p_session_id      uuid,
  p_organizer_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session_id      uuid := close_session.p_session_id;
  v_organizer_token text := close_session.p_organizer_token;
  v_session         record;
begin
  -- ---------------------------------------------------------------------------
  -- Argument checks
  -- ---------------------------------------------------------------------------
  if v_session_id is null then
    raise exception 'sessionId is required' using errcode = 'CS003';
  end if;

  if v_organizer_token is null or btrim(v_organizer_token) = '' then
    raise exception 'organizerToken is required' using errcode = 'CS003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Lock the session row
  -- ---------------------------------------------------------------------------
  select s.id, s.status
    into v_session
    from public.sessions s
   where s.id = v_session_id
     for update;

  if not found then
    raise exception 'Session not found' using errcode = 'CS001';
  end if;

  -- ---------------------------------------------------------------------------
  -- Authorize: the organizer token must belong to this session
  -- (checked before the state, so non-organizers learn nothing about it)
  -- ---------------------------------------------------------------------------
  if not exists (
    select 1
      from public.organizers o
     where o.session_id = v_session_id
       and o.organizer_token = v_organizer_token
  ) then
    raise exception 'Organizer token is not valid for this session' using errcode = 'CS002';
  end if;

  -- ---------------------------------------------------------------------------
  -- State check
  -- ---------------------------------------------------------------------------
  if v_session.status = 'CLOSED' then
    raise exception 'Session is already closed' using errcode = 'CS004';
  end if;

  if v_session.status <> 'ACTIVE' then
    raise exception 'Only ACTIVE sessions can be closed (status=%)', v_session.status
      using errcode = 'CS005';
  end if;

  -- ---------------------------------------------------------------------------
  -- Close (session row only)
  -- ---------------------------------------------------------------------------
  update public.sessions s
     set status = 'CLOSED'
   where s.id = v_session_id
  returning s.id, s.status, s.published, s.session_name
    into v_session;

  return jsonb_build_object(
    'sessionId',   v_session.id,
    'status',      v_session.status,
    'published',   v_session.published,
    'sessionName', v_session.session_name
  );
end;
$$;

-- Only the service role (ctx.supabaseAdmin) may call this function.
revoke all on function public.close_session(uuid, text)
  from public, anon, authenticated;
grant execute on function public.close_session(uuid, text)
  to service_role;


-- =============================================================================
-- get_my_assignment: accept ACTIVE or CLOSED sessions
--
-- Identical to 20261030150000_get_my_assignment.sql except for the session
-- status check. A DRAFT (unpublished) session still returns GA003.
-- =============================================================================

create or replace function public.get_my_assignment(
  p_browser_token text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_browser_token text := get_my_assignment.p_browser_token;
  v_participant   record;
  v_session       record;
  v_my_color      record;
  v_gift_color    record;
begin
  -- ---------------------------------------------------------------------------
  -- Argument checks
  -- ---------------------------------------------------------------------------
  if v_browser_token is null or btrim(v_browser_token) = '' then
    raise exception 'browserToken is required' using errcode = 'GA004';
  end if;

  if v_browser_token !~ '^BT_[A-Za-z0-9_-]{43}$' then
    raise exception 'browserToken has an invalid format' using errcode = 'GA004';
  end if;

  -- ---------------------------------------------------------------------------
  -- Participant lookup: browser_token is globally unique
  -- (ux_participants_browser_token), so this matches at most one row.
  -- ---------------------------------------------------------------------------
  select p.id, p.session_id, p.participant_name, p.active, p.assigned_color_id
    into v_participant
    from public.participants p
   where p.browser_token = v_browser_token;

  if not found then
    raise exception 'Participant not found' using errcode = 'GA001';
  end if;

  if not v_participant.active then
    raise exception 'Participant is inactive' using errcode = 'GA002';
  end if;

  if v_participant.assigned_color_id is null then
    raise exception 'Participant has no assigned color' using errcode = 'GA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Session must be published and ACTIVE or CLOSED (checked, never returned)
  -- ---------------------------------------------------------------------------
  select s.status, s.published
    into v_session
    from public.sessions s
   where s.id = v_participant.session_id;

  if not found
     or v_session.status not in ('ACTIVE', 'CLOSED')
     or not v_session.published then
    raise exception 'Assignment is not available for this session' using errcode = 'GA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- My color: assigned_color_id -> colors -> color_catalog
  -- ---------------------------------------------------------------------------
  select c.target_color_id, cc.color_name, cc.hex_color
    into v_my_color
    from public.colors c
    join public.color_catalog cc on cc.id = c.color_catalog_id
   where c.id = v_participant.assigned_color_id
     and c.session_id = v_participant.session_id;

  if not found then
    raise exception 'Assigned color is missing' using errcode = 'GA003';
  end if;

  if v_my_color.target_color_id is null then
    raise exception 'Assigned color has no gift target' using errcode = 'GA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Gift color: target_color_id -> colors -> color_catalog
  -- ---------------------------------------------------------------------------
  select cc.color_name, cc.hex_color
    into v_gift_color
    from public.colors t
    join public.color_catalog cc on cc.id = t.color_catalog_id
   where t.id = v_my_color.target_color_id
     and t.session_id = v_participant.session_id
     and t.id <> v_participant.assigned_color_id;

  if not found then
    raise exception 'Gift color is missing or invalid' using errcode = 'GA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Result (whitelisted fields only)
  -- ---------------------------------------------------------------------------
  return jsonb_build_object(
    'participantId',   v_participant.id,
    'participantName', v_participant.participant_name,
    'myColor', jsonb_build_object(
      'name',     v_my_color.color_name,
      'hexColor', v_my_color.hex_color
    ),
    'giftColor', jsonb_build_object(
      'name',     v_gift_color.color_name,
      'hexColor', v_gift_color.hex_color
    )
  );
end;
$$;

revoke all on function public.get_my_assignment(text)
  from public, anon, authenticated;
grant execute on function public.get_my_assignment(text)
  to service_role;


-- =============================================================================
-- recover_assignment: accept ACTIVE or CLOSED sessions
--
-- Identical to 20261030160000_recover_assignment.sql except for the session
-- status check. A DRAFT (unpublished) session still returns RA003.
-- =============================================================================

create or replace function public.recover_assignment(
  p_recovery_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_recovery_code text := recover_assignment.p_recovery_code;
  v_participant   record;
  v_session       record;
  v_my_color      record;
  v_gift_color    record;
begin
  -- ---------------------------------------------------------------------------
  -- Argument checks
  -- ---------------------------------------------------------------------------
  if v_recovery_code is null or btrim(v_recovery_code) = '' then
    raise exception 'recoveryCode is required' using errcode = 'RA004';
  end if;

  if v_recovery_code !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}(-[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}){2}$' then
    raise exception 'recoveryCode has an invalid format' using errcode = 'RA004';
  end if;

  -- ---------------------------------------------------------------------------
  -- Participant lookup: recovery_code is globally unique
  -- (ux_participants_recovery_code), so this matches at most one row.
  -- ---------------------------------------------------------------------------
  select p.id, p.session_id, p.participant_name, p.browser_token, p.active, p.assigned_color_id
    into v_participant
    from public.participants p
   where p.recovery_code = v_recovery_code;

  if not found then
    raise exception 'Participant not found' using errcode = 'RA001';
  end if;

  if not v_participant.active then
    raise exception 'Participant is inactive' using errcode = 'RA002';
  end if;

  if v_participant.assigned_color_id is null then
    raise exception 'Participant has no assigned color' using errcode = 'RA003';
  end if;

  if v_participant.browser_token is null then
    raise exception 'Participant has no browser token' using errcode = 'RA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Session must be published and ACTIVE or CLOSED (checked, never returned)
  -- ---------------------------------------------------------------------------
  select s.status, s.published
    into v_session
    from public.sessions s
   where s.id = v_participant.session_id;

  if not found
     or v_session.status not in ('ACTIVE', 'CLOSED')
     or not v_session.published then
    raise exception 'Assignment is not available for this session' using errcode = 'RA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- My color: assigned_color_id -> colors -> color_catalog
  -- ---------------------------------------------------------------------------
  select c.target_color_id, cc.color_name, cc.hex_color
    into v_my_color
    from public.colors c
    join public.color_catalog cc on cc.id = c.color_catalog_id
   where c.id = v_participant.assigned_color_id
     and c.session_id = v_participant.session_id;

  if not found then
    raise exception 'Assigned color is missing' using errcode = 'RA003';
  end if;

  if v_my_color.target_color_id is null then
    raise exception 'Assigned color has no gift target' using errcode = 'RA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Gift color: target_color_id -> colors -> color_catalog
  -- ---------------------------------------------------------------------------
  select cc.color_name, cc.hex_color
    into v_gift_color
    from public.colors t
    join public.color_catalog cc on cc.id = t.color_catalog_id
   where t.id = v_my_color.target_color_id
     and t.session_id = v_participant.session_id
     and t.id <> v_participant.assigned_color_id;

  if not found then
    raise exception 'Gift color is missing or invalid' using errcode = 'RA003';
  end if;

  -- ---------------------------------------------------------------------------
  -- Result (whitelisted fields only)
  -- ---------------------------------------------------------------------------
  return jsonb_build_object(
    'participantId',   v_participant.id,
    'participantName', v_participant.participant_name,
    'browserToken',    v_participant.browser_token,
    'myColor', jsonb_build_object(
      'name',     v_my_color.color_name,
      'hexColor', v_my_color.hex_color
    ),
    'giftColor', jsonb_build_object(
      'name',     v_gift_color.color_name,
      'hexColor', v_gift_color.hex_color
    )
  );
end;
$$;

revoke all on function public.recover_assignment(text)
  from public, anon, authenticated;
grant execute on function public.recover_assignment(text)
  to service_role;
