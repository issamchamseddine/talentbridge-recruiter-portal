-- One call that returns everything the search engine needs (55 candidates + flagged files).
create or replace function rc_search_data() returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'candidates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'full_name', full_name, 'city', city, 'country', country, 'years_total', years_total,
        'current_title', current_title, 'skills', skills, 'languages', languages, 'source_file', source_file,
        'read_method', read_method, 'needs_review', needs_review, 'review_reason', review_reason,
        'cv_date', cv_date, 'cv_text', cv_text) order by full_name)
      from rc_candidates where status = 'active'), '[]'::jsonb),
    'files', coalesce((
      select jsonb_agg(jsonb_build_object(
        'file_name', file_name, 'status', status, 'note', note, 'read_method', read_method, 'needs_review', needs_review)
        order by file_name)
      from rc_cv_files where status = 'unreadable' or needs_review), '[]'::jsonb)
  );
$$;
