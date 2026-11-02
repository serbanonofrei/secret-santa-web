-- =============================================================================
-- list_colors
--
-- Returns the color catalog for the organizer color picker:
--   { "colors": [ { "id": 1, "name": "PURPLE", "hexColor": "#800080" }, ... ] }
--
-- * Only colors that are currently eligible for create-session selection,
--   i.e. enabled = true. This is the same filter create_session_with_colors
--   applies to allowedColors, so every color shown in the picker is accepted
--   by create-session (barring a color being disabled in between, which
--   create-session still reports as UNKNOWN_COLORS, 422).
--   Disabled colors are omitted entirely; no enabled flag is returned.
-- * Sorted by color_name, then id so the order is stable.
-- * Only id, color_name and hex_color are returned; no other catalog columns.
--
-- Read-only: no rows are written or locked.
--
-- Custom SQLSTATEs (mapped to HTTP codes by the list-colors Edge Function):
--   LC001 -> unexpected database error                    (500)
-- =============================================================================

create or replace function public.list_colors()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_colors jsonb;
begin
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'id',       cc.id,
               'name',     cc.color_name,
               'hexColor', cc.hex_color
             )
             order by cc.color_name, cc.id
           ),
           '[]'::jsonb
         )
    into v_colors
    from public.color_catalog cc
   where cc.enabled = true;

  return jsonb_build_object('colors', v_colors);
exception
  when others then
    -- Log the real cause server-side; the client only sees LC001.
    raise log 'list_colors failed: % (SQLSTATE %)', sqlerrm, sqlstate;
    raise exception 'Failed to list colors' using errcode = 'LC001';
end;
$$;

-- Only the service role (ctx.supabaseAdmin) may call this function.
revoke all on function public.list_colors()
  from public, anon, authenticated;
grant execute on function public.list_colors()
  to service_role;
