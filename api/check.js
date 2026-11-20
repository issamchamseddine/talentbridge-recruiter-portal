// Write endpoint: mark a scanned CV as checked (or flag it again). Protected by an access code kept in Vercel settings.
module.exports = async (req, res) => {
  try {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
    const { candidate_id, action, code } = req.body || {};
    if (!process.env.ACTION_CODE || code !== process.env.ACTION_CODE) return res.status(401).json({ error: 'Wrong access code' });
    const id = Number(candidate_id);
    if (!id || !['check', 'flag'].includes(action)) return res.status(400).json({ error: 'candidate_id and action (check or flag) are required' });
    const fn = action === 'check' ? 'rc_mark_checked' : 'rc_flag_for_review';
    const body = action === 'check' ? { p_candidate_id: id, p_user: 'recruiter (portal)' } : { p_candidate_id: id };
    const r = await fetch(process.env.SUPABASE_URL + '/rest/v1/rpc/' + fn, {
      method: 'POST',
      headers: { apikey: process.env.SUPABASE_SERVICE_KEY, Authorization: 'Bearer ' + process.env.SUPABASE_SERVICE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    if (!r.ok) throw new Error((await r.text()).slice(0, 200));
    res.status(200).json(await r.json());
  } catch (e) {
    res.status(500).json({ error: String(e.message || e) });
  }
};
