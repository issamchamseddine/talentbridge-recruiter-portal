# TalentBridge recruiter copilot

A hiring copilot for a remote-staffing agency. A recruiter works in Slack and approves every step with one click.

**Live portal:** (add your Vercel link here)

## What it does

| Step | How |
|---|---|
| Client call transcript becomes a job description | Paste the transcript in `#new-roles`. Gemini writes the job description and the search requirements. It is posted in Slack with **Approve / Reject**. |
| Every CV is searchable | Upload CVs (PDF or Word) through an n8n form. Text is extracted, scanned CVs are read by AI vision, Gemini turns each CV into structured facts (skills with years, languages, location), and a database function stores them. An updated CV replaces the old one, duplicates and older versions are ignored. |
| Ask in plain English | Ask in `#ask-candidates`. Gemini only turns the question into requirements; plain code filters, scores (0-100) and writes the reason from stored facts, so it cannot invent a candidate. |
| Approve, then outreach | Approving a job description creates the shortlist. Approving candidates starts a 3-email sequence that stops as soon as the candidate replies. |
| Portal | Open roles with shortlists, candidates per pipeline stage, flagged CVs, and the bot's test score. |

## The real work (rules the system follows)

- Nothing reaches a candidate or a client until a recruiter clicks Approve. Outreach only touches candidates in the Approved stage. While test mode is on, every email is delivered to the recruiter's own inbox.
- No good match: the bot says "No suitable candidate found" and names nobody. A place that no CV lists is reported as such.
- Every recommendation names the CV file it came from, with a link that opens it.
- Unreadable CVs are never skipped silently: they are flagged in the Slack summary of the upload, in search answers, and in the portal. Scanned CVs are read by OCR and stay flagged until a recruiter marks them as checked.

## Architecture

```
Slack (#new-roles, #ask-candidates, buttons)
        |
      n8n  ---- Gemini (reads CVs, reads questions, writes job descriptions)
        |
    Supabase (Postgres + file storage)  <----  Portal (this repo, Vercel)
        |
      Gmail (outreach)           GoHighLevel (candidate pipeline, see docs)
```

- `index.html` is the whole portal front end. `api/data.js` reads the database; `api/check.js` marks a scanned CV as checked (needs the access code).
- `sql/` holds the database: tables (prefix `rc_`), the atomic functions for storing CVs, approvals and outreach, and the portal helpers. Run the files in order.
- `n8n/` holds the exported workflows.

## Scoring method

`score = 60` (meets every must-have) `+ up to 20` (experience beyond the minimum) `+ up to 10` (total years of experience) `+ up to 10` (nice-to-haves). Someone missing a must-have is never shown. Equivalent skills match each other (for example executive support and calendar and inbox management).

## Pipeline stages

Shortlisted, Approved, Contacted, Replied, Interview, Placed, Rejected.

## Setup

1. **Supabase:** run the files in `sql/` in order (SQL Editor). Create a public storage bucket named `cvs` and upload the CV files.
2. **Vercel:** import this repo. Framework preset: Other. Add three environment variables: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` (server side only, never in the page), `ACTION_CODE` (the code a recruiter types to mark a CV as checked).
3. **n8n:** import the workflows, set the credentials (Supabase, Gemini, Slack bot token, Gmail), open each workflow's config node and set the Supabase URL.
4. **Slack:** an app with scopes `chat:write`, `chat:write.public`, `channels:history`, `channels:read`; Event Subscriptions (`message.channels`) pointing to RC-2A; Interactivity pointing to RC-2B. Socket Mode must be off.

## Security notes

- The Supabase service key lives only in Vercel and n8n credentials. Tables have row level security on with no public policies.
- The portal's read endpoint is public because the demo data is fake; write actions need the access code.
- Slack request signatures are not verified in this version; production use should add it.

## Test results

The test page shows 10 questions with known right answers, taken from the answer key of the generated data set, and the score of the last run. The few-shot examples inside the question parser use different skills from the 10 questions.

## Known limits

- The course GoHighLevel API token is read-only and the Inbound Webhook trigger is a paid feature, so the GoHighLevel pipeline is fed through a standard GHL form and workflow (see `docs/ghl.md`).
- CV originals are shown as they were uploaded; converting everything to PDF would need a document converter that n8n Cloud does not have.
- Google keeps apps in testing mode connected for 7 days: reconnect Gmail before sending.
