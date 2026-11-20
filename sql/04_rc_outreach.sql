-- RC-3: outreach email sequence, driven by the database. Safe to run more than once.
alter table rc_outreach
  add column if not exists thread_id text,
  add column if not exists message_id text,
  add column if not exists to_email text;

-- 1) Create the sequence steps for newly approved candidates and return the current state of every
--    candidate in outreach: who has a thread, how many emails were sent, and what is due next.
create or replace function rc_outreach_prepare(p_delays int[]) returns jsonb
language plpgsql as $$
declare out jsonb;
begin
  insert into rc_outreach (shortlist_id, step, send_at)
  select s.id, d.step, now() + make_interval(mins => d.delay)
    from rc_shortlists s
   cross join lateral (select u.ord::int as step, u.delay
                         from unnest(p_delays) with ordinality as u(delay, ord)) d
   where s.stage = 'Approved'
     and not exists (select 1 from rc_outreach o where o.shortlist_id = s.id)
  on conflict (shortlist_id, step) do nothing;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.shortlist_id), '[]'::jsonb) into out
  from (
    select s.id as shortlist_id, s.cv_file, c.full_name, c.email, r.title, r.client_company,
           (select o.thread_id  from rc_outreach o where o.shortlist_id = s.id and o.thread_id  is not null order by o.step limit 1) as thread_id,
           (select o.message_id from rc_outreach o where o.shortlist_id = s.id and o.message_id is not null order by o.step limit 1) as first_message_id,
           (select count(*) from rc_outreach o where o.shortlist_id = s.id and o.status = 'sent') as sent_count,
           n.id as next_outreach_id, n.step as next_step, (n.send_at <= now()) as due
      from rc_shortlists s
      join rc_candidates c on c.id = s.candidate_id
      join rc_roles r on r.id = s.role_id
      left join lateral (select o.id, o.step, o.send_at from rc_outreach o
                          where o.shortlist_id = s.id and o.status = 'pending' order by o.step limit 1) n on true
     where s.stage in ('Approved', 'Contacted')
  ) x
  where x.thread_id is not null or x.next_outreach_id is not null;
  return jsonb_build_object('rows', out);
end $$;

-- 2) Record that an email was sent; the candidate becomes "Contacted".
create or replace function rc_outreach_mark_sent(p_outreach_id bigint, p_thread text, p_message text, p_to text, p_subject text, p_body text) returns jsonb
language plpgsql as $$
declare sid bigint;
begin
  update rc_outreach
     set status = 'sent', sent_at = now(), thread_id = coalesce(p_thread, thread_id), message_id = coalesce(p_message, message_id),
         to_email = p_to, subject = p_subject, body = p_body
   where id = p_outreach_id and status = 'pending'
  returning shortlist_id into sid;
  if sid is not null then
    update rc_shortlists set stage = 'Contacted', updated_at = now() where id = sid and stage = 'Approved';
  end if;
  return jsonb_build_object('ok', sid is not null);
end $$;

-- 3) The candidate replied: stop the sequence.
create or replace function rc_mark_replied(p_shortlist_id bigint) returns jsonb
language plpgsql as $$
declare changed boolean;
begin
  update rc_shortlists set stage = 'Replied', updated_at = now()
   where id = p_shortlist_id and stage in ('Approved', 'Contacted');
  changed := found;
  update rc_outreach set status = 'stopped' where shortlist_id = p_shortlist_id and status = 'pending';
  return jsonb_build_object('changed', changed);
end $$;
