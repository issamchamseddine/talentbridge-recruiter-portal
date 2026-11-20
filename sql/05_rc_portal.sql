-- Portal helpers: a recruiter can mark a scanned CV as checked (or flag it again).
create or replace function rc_mark_checked(p_candidate_id bigint, p_user text) returns jsonb
language plpgsql as $$
declare n int;
begin
  update rc_candidates
     set needs_review = false,
         review_reason = 'Checked by ' || coalesce(p_user, 'a recruiter') || ' on ' || to_char(now(), 'YYYY-MM-DD'),
         updated_at = now()
   where id = p_candidate_id and needs_review;
  get diagnostics n = row_count;
  update rc_cv_files
     set needs_review = false,
         note = 'Checked by ' || coalesce(p_user, 'a recruiter') || ' on ' || to_char(now(), 'YYYY-MM-DD')
   where candidate_id = p_candidate_id and needs_review;
  return jsonb_build_object('changed', n > 0);
end $$;

create or replace function rc_flag_for_review(p_candidate_id bigint) returns jsonb
language plpgsql as $$
declare n int;
begin
  update rc_candidates
     set needs_review = true,
         review_reason = 'Image-only scan - text was read by OCR, please check the details',
         updated_at = now()
   where id = p_candidate_id and read_method = 'ocr' and not needs_review;
  get diagnostics n = row_count;
  update rc_cv_files
     set needs_review = true, note = 'Image-only scan - text was read by OCR, please check the details'
   where candidate_id = p_candidate_id and status = 'current' and read_method = 'ocr' and not needs_review;
  return jsonb_build_object('changed', n > 0);
end $$;
