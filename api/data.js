// Read-only data endpoint for the portal. The Supabase service key stays on the server (Vercel environment variables).
const URL_ = process.env.SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_KEY;
const H = { apikey: KEY, Authorization: 'Bearer ' + KEY };

async function q(path) {
  const r = await fetch(URL_ + '/rest/v1/' + path, { headers: H });
  if (!r.ok) throw new Error(path.split('?')[0] + ': ' + r.status + ' ' + (await r.text()).slice(0, 200));
  return r.json();
}

// Read-only look at the GoHighLevel candidate pipeline (the course token can read, but not write).
async function ghl() {
  const t = process.env.GHL_TOKEN, loc = process.env.GHL_LOCATION_ID || 'yLiKZKvk2CeI2ckIqd1L';
  const name = process.env.GHL_PIPELINE_NAME || 'IC - Candidate Pipeline';
  if (!t) return { available: false, reason: 'GHL_TOKEN is not set in Vercel' };
  const H = { Authorization: 'Bearer ' + t, Version: '2021-07-28', Accept: 'application/json' };
  try {
    const pr = await fetch('https://services.leadconnectorhq.com/opportunities/pipelines?locationId=' + loc, { headers: H });
    const pj = await pr.json();
    if (!pr.ok) return { available: false, reason: pj.message || 'GHL answered ' + pr.status };
    const p = (pj.pipelines || []).find(x => x.name === name);
    if (!p) return { available: false, reason: 'No pipeline named "' + name + '" in GoHighLevel yet' };
    const stage = Object.fromEntries((p.stages || []).map(s => [s.id, s.name]));
    const or = await fetch('https://services.leadconnectorhq.com/opportunities/search?location_id=' + loc + '&pipeline_id=' + p.id + '&limit=100', { headers: H });
    const oj = await or.json();
    if (!or.ok) return { available: false, reason: oj.message || 'GHL answered ' + or.status };
    const byEmail = {};
    for (const o of (oj.opportunities || [])) { const e = String((o.contact && o.contact.email) || '').toLowerCase(); if (e) byEmail[e] = { stage: stage[o.pipelineStageId] || 'Unknown stage' }; }
    return { available: true, pipeline: p.name, count: (oj.opportunities || []).length, byEmail };
  } catch (e) { return { available: false, reason: String(e.message || e) }; }
}

module.exports = async (req, res) => {
  try {
    if (!URL_ || !KEY) throw new Error('SUPABASE_URL and SUPABASE_SERVICE_KEY are not set in the Vercel project settings');
    const [roles, shortlists, outreach, flagged, candidates, latest, ghlInfo] = await Promise.all([
      q('rc_roles?select=id,title,client_company,client_name,status,requirements,jd_markdown,created_at,approved_by,approved_at&order=created_at.desc'),
      q('rc_shortlists?select=id,role_id,candidate_id,score,reason,cv_file,stage,approved_at,rc_candidates(full_name,email,phone,city,country,read_method,needs_review)&order=score.desc'),
      q('rc_outreach?select=shortlist_id,step,status'),
      q('rc_cv_files?select=file_name,status,note,read_method,needs_review,candidate_id,rc_candidates(full_name)&or=(status.eq.unreadable,needs_review.eq.true)&order=file_name'),
      q('rc_candidates?select=id,full_name,source_file,read_method,needs_review,review_reason&status=eq.active&order=full_name'),
      q('rc_test_runs?select=run_id&order=created_at.desc&limit=1'),
      ghl()
    ]);
    let tests = [];
    if (latest.length) tests = await q('rc_test_runs?select=run_id,question_no,question,expected,bot_answer,passed,details,created_at&run_id=eq.' + encodeURIComponent(latest[0].run_id) + '&order=question_no');
    res.setHeader('Cache-Control', 'no-store');
    res.status(200).json({
      cv_base: URL_ + '/storage/v1/object/public/cvs/',
      roles, shortlists, outreach, flagged, ghl: ghlInfo,
      candidates_total: candidates.length,
      checked_scans: candidates.filter(c => c.read_method === 'ocr' && !c.needs_review),
      tests
    });
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
};
