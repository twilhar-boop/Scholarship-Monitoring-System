# Scholarship Renewal System (Supabase + HTML/CSS/JavaScript)

## 1. Supabase setup
1. Create a Supabase project.
2. Open **SQL Editor**, paste and run `supabase/schema.sql`.
3. In **Project Settings → API**, copy the Project URL and anon/publishable key into `js/app.js`. Never expose the service-role key in browser code.
4. Create the first staff account in **Authentication → Users → Add user**. Confirm the user, copy the UUID, then run this SQL after replacing the UUID:
   ```sql
   insert into public.profiles(id,role,full_name)
   values ('PASTE-AUTH-UUID-HERE','staff','Scholarship Staff');
   ```
5. Deploy the Edge Function from this folder:
   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase functions deploy create-scholar
   ```
   Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to deployed functions. Do not paste the service-role key into `app.js`.
6. Host the folder using VS Code Live Server or any static web host. Open `index.html`, sign in as staff, and register scholar accounts.

## 2. Roles and security
- `profiles`, `submissions`, and `audit_history` have RLS enabled.
- Scholars can select only their own submissions and insert their own pending submissions.
- Staff-only RPC functions verify, evaluate, and decide renewals. The server checks the role and prevents approving deficient records.
- `audit_history` records verification, evaluation, and renewal changes with actor and timestamp.
- This is an instructional MVP. Before production, restrict CORS to the deployed origin, add rate limits, review grants and policies, and test all RLS policies with separate accounts.

## 3. Fictional policies
- Merit: maximum GWA 1.75; minimum 18 units; zero failed, incomplete, or dropped subjects.
- Community: maximum GWA 2.25; minimum 15 units; zero failed and incomplete subjects; at most one dropped subject.
- Deadline: 2026-10-30 17:00 Asia/Manila. The SQL compares `timestamptz` instants; a submission exactly at deadline is on time.
- Evaluation is available only after evidence is Verified. Approved renewal requires a Compliant evaluation. Staff may hold a compliant or deficient verified/evaluated record.

## 4. Seed records and required test cases
Create six fictional accounts using the staff form, then submit the required test values for A01–A06. For A01 and A05, the deadline condition requires the server's actual `submitted_at`; do not change production timestamps to simulate a test. For repeatable tests, use a separate test database or controlled test-only SQL fixtures with timestamps. A06 remains Pending until staff verifies it.
The provided SQL does not automatically seed six auth-linked users because Auth user UUIDs are created by Supabase. Use the staff registration form to create them, then enter the test submissions from each account. Suggested IDs: A01 through A06.

## 5. Mandatory test results template
Record real results after testing. Do not mark a test Pass unless you have screenshot or other evidence.
| Test ID | Input/action | Expected result | Actual result | Pass/Fail | Evidence |
|---|---|---|---|---|---|
| TC01 | Merit; GWA 1.75; 18 units; zero counts; submitted at deadline | Compliant | To be tested | Pending | Screenshot |
| TC02 | Merit; GWA 1.76; other values pass | With Deficiency; GWA reason | To be tested | Pending | Screenshot |
| TC03 | Community; GWA 2.25; 15 units; one dropped | Compliant | To be tested | Pending | Screenshot |
| TC04 | Community; GWA 2.25; 14 units; one incomplete | With Deficiency; units and incomplete reasons | To be tested | Pending | Screenshot |
| TC05 | Merit; GWA 1.50; one failed; submitted after deadline | With Deficiency; failed subject and late reasons | To be tested | Pending | Screenshot |
| TC06 | Pending evidence; evaluate/approve | Both blocked until verified and evaluated | To be tested | Pending | Screenshot |
| TC07 | Duplicate semester or invalid GWA/count | Rejected with clear message | To be tested | Pending | Screenshot |
| TC08 | Scholar tries to read another scholar or call staff RPC | RLS/RPC denies access | To be tested | Pending | Screenshot |
| TC09 | Staff returns; scholar corrects/resubmits; refresh | Pending verification; audit history preserved | To be tested | Pending | Screenshot |
| TC10 | Staff approves compliant and holds deficient; scholar attempts decision change | Approved/Held enforced; scholar denied | To be tested | Pending | Screenshot |

## Known limitations to report honestly
- Seeded six accounts and their special timestamps must be created as test fixtures; Auth UUIDs are project-specific.
- The current UI shows audit history through the database, but does not yet include a dedicated audit-history page.
- Returned submissions need a correction UI before this MVP fully satisfies TC09; the current schema/RLS is ready for a controlled correction flow but scholar update is intentionally not granted yet to avoid privilege escalation. Add a secure correction RPC before claiming TC09 passes.
- Dashboard summary counts submissions, not a separate scholar roster. Scholars without a submission are not included in the assigned-scholar count yet.
- Do not use real student grades or personal data; all sample records are fictional.
