-- RC-2B: atomic, double-click-safe approval functions.

-- Approve or reject a job description (only works while it is pending).
create or replace function rc_decide_role(p_role_id bigint, p_decision text, p_user text) returns jsonb
language plpgsql as $$
declare r rc_roles%rowtype;
begin
  update rc_roles
     set status = case when p_decision = 'approve' then 'open' else 'rejected' end,
         approved_by = p_user, approved_at = now()
   where id = p_role_id and status = 'pending_approval'
  returning * into r;
  if not found then return jsonb_build_object('changed', false); end if;
  return jsonb_build_object('changed', true, 'role', to_jsonb(r));
end $$;

-- Save the top candidates of a role as its shortlist and return them with names.
create or replace function rc_save_shortlist(p_role_id bigint, p_results jsonb) returns jsonb
language plpgsql as $$
declare out jsonb;
begin
  insert into rc_shortlists (role_id, candidate_id, score, reason, cv_file)
  select p_role_id, (r->>'candidate_id')::bigint, (r->>'score')::int, r->>'reason', r->>'cv_file'
    from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) r
  on conflict (role_id, candidate_id) do update
     set score = excluded.score, reason = excluded.reason, cv_file = excluded.cv_file, updated_at = now()
   where rc_shortlists.stage = 'Shortlisted';

  select coalesce(jsonb_agg(jsonb_build_object(
           'shortlist_id', s.id, 'candidate_id', s.candidate_id, 'full_name', c.full_name,
           'score', s.score, 'reason', s.reason, 'cv_file', s.cv_file, 'stage', s.stage)
         order by s.score desc, c.full_name), '[]'::jsonb)
    into out
    from rc_shortlists s join rc_candidates c on c.id = s.candidate_id
   where s.role_id = p_role_id
     and s.candidate_id in (select (r->>'candidate_id')::bigint from jsonb_array_elements(coalesce(p_results, '[]'::jsonb)) r);
  return jsonb_build_object('rows', out);
end $$;

-- Approve one candidate (p_shortlist_id) or all still-waiting candidates (null) of a role.
create or replace function rc_approve_shortlist(p_role_id bigint, p_shortlist_id bigint, p_user text) returns jsonb
language plpgsql as $$
declare res jsonb;
begin
  with upd as (
    update rc_shortlists s
       set stage = 'Approved', approved_by = p_user, approved_at = now(), updated_at = now()
     where s.role_id = p_role_id and s.stage = 'Shortlisted' and (p_shortlist_id is null or s.id = p_shortlist_id)
    returning s.id, s.candidate_id)
  select jsonb_build_object('count', count(*), 'names', coalesce(jsonb_agg(c.full_name order by c.full_name), '[]'::jsonb))
    into res
    from upd join rc_candidates c on c.id = upd.candidate_id;
  return res;
end $$;
