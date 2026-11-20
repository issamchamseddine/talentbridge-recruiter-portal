# GoHighLevel pipeline

Status: to be completed after the GHL form route is tested.

What is known about the course GoHighLevel account:
- The API token provided by the course is read-only (creating a contact fails with "token is not authorized for this scope").
- The workflow trigger "Inbound Webhook" is a premium trigger with a per-execution charge, so it is not used.
- A standard GHL form with a "Form Submitted" workflow is the planned route: n8n submits the candidate to the form, and a GHL workflow creates the opportunity in the candidate pipeline.

The candidate pipeline stages are mirrored in Supabase (`rc_shortlists.stage`), and the portal always shows the stage from Supabase.
