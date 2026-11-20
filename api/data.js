// Read-only data endpoint for the portal. The Supabase service key stays on the server (Vercel environment variables).
const URL_ = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_KEY;
const H = { apikey: KEY, Authorization: 'Bearer ' + KEY };

async function q(path) {
  const r = await fetch(URL_ + '/rest/v1/' + path, { headers: H });
  if (!r.ok) throw new Error(path.split('?')[0] + ': ' + r.status + ' ' + (await r.text()).slice(0, 200));
  return r.json();
}

module.exports = async (req, res) => {
  try {
    if (!URL_ || !KEY) throw new Error('SUPABASE_URL and SUPABASE_SERVICE_KEY are not set in the Vercel project settings');
    const [roles, shortlists, outreach, flagged, candidates, latest] = await Promise.all([
      q('rc_roles?select=id,title,client_company,client_name,status,requirements,jd_markdown,created_at,approved_by,approved_at&order=created_at.desc'),
      q('rc_shortlists?select=id,role_id,candidate_id,score,reason,cv_file,stage,approved_at,rc_candidates(full_name,city,country,read_method,needs_review)&order=score.desc'),
      q('rc_outreach?select=shortlist_id,step,status'),
      q('rc_cv_files?select=file_name,status,note,read_method,needs_review,candidate_id,rc_candidates(full_name)&or=(status.eq.unreadable,needs_review.eq.true)&order=file_name'),
      q('rc_candidates?select=id,full_name,source_file,read_method,needs_review,review_reason&status=eq.active&order=full_name'),
      q('rc_test_runs?select=run_id&order=created_at.desc&limit=1')
    ]);
    let tests = [];
    if (latest.length) tests = await q('rc_test_runs?select=run_id,question_no,question,expected,bot_answer,passed,details,created_at&run_id=eq.' + encodeURIComponent(latest[0].run_id) + '&order=question_no');
    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json({
      cv_base: URL_ + '/storage/v1/object/public/cvs/',
      roles, shortlists, outreach, flagged,
      candidates_total: candidates.length,
      checked_scans: candidates.filter(c => c.read_method === 'ocr' && !c.needs_review),
      tests
    });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
};
