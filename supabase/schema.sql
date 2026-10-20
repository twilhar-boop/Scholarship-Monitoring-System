-- Run in Supabase SQL Editor. Fictional scholarship policy and seeded test data.
create extension if not exists pgcrypto;
create table if not exists public.programs(
 id text primary key check(id in ('merit','community')), name text not null,
 max_gwa numeric(3,2) not null check(max_gwa between 1 and 5),
 min_units integer not null check(min_units>=0), max_failed integer not null default 0 check(max_failed>=0),
 max_incomplete integer not null default 0 check(max_incomplete>=0), max_dropped integer not null check(max_dropped>=0),
 deadline timestamptz not null
);
insert into public.programs(id,name,max_gwa,min_units,max_failed,max_incomplete,max_dropped,deadline) values
('merit','Merit Scholar',1.75,18,0,0,0,'2026-10-30 17:00:00+08'),
('community','Community Scholar',2.25,15,0,0,1,'2026-10-30 17:00:00+08')
on conflict(id) do update set name=excluded.name,max_gwa=excluded.max_gwa,min_units=excluded.min_units,max_failed=excluded.max_failed,max_incomplete=excluded.max_incomplete,max_dropped=excluded.max_dropped,deadline=excluded.deadline;
create table if not exists public.profiles(
 id uuid primary key references auth.users(id) on delete cascade,
 role text not null check(role in ('staff','scholar')), student_id text unique,
 full_name text not null, program_id text references public.programs(id),
 created_at timestamptz not null default now(),
 check((role='staff') or (role='scholar' and student_id is not null and program_id is not null))
);
create table if not exists public.submissions(
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 academic_year text not null, semester integer not null check(semester in (1,2)),
 gwa numeric(3,2) not null check(gwa between 1 and 5),
 units_enrolled integer not null check(units_enrolled>=0), failed_subjects integer not null check(failed_subjects>=0),
 incomplete_grades integer not null check(incomplete_grades>=0), dropped_subjects integer not null check(dropped_subjects>=0),
 academic_summary text not null check(length(trim(academic_summary))>=10),
 evidence_reference text not null check(length(trim(evidence_reference))>0),
 submitted_at timestamptz not null default now(),
 verification_status text not null default 'Pending' check(verification_status in ('Pending','Verified','Returned')),
 verification_reason text, evaluation_status text check(evaluation_status in ('Compliant','With Deficiency')),
 evaluation_reasons text, evaluated_at timestamptz,
 renewal_status text check(renewal_status in ('Approved','Held')), decision_note text, decided_by uuid references public.profiles(id), decided_at timestamptz,
 unique(user_id,academic_year,semester)
);
create table if not exists public.audit_history(
 id bigint generated always as identity primary key, submission_id uuid not null references public.submissions(id) on delete cascade,
 action text not null, old_value jsonb, new_value jsonb, note text, actor uuid references public.profiles(id),
 created_at timestamptz not null default now()
);
create or replace function public.current_role() returns text language sql stable security definer set search_path=public as $$
 select role from public.profiles where id=auth.uid()
$$;
alter table public.programs enable row level security;
alter table public.profiles enable row level security;
alter table public.submissions enable row level security;
alter table public.audit_history enable row level security;
drop policy if exists "programs readable" on public.programs;
create policy "programs readable" on public.programs for select to authenticated using(true);
drop policy if exists "profile read own or staff" on public.profiles;
create policy "profile read own or staff" on public.profiles for select to authenticated using(id=auth.uid() or public.current_role()='staff');
drop policy if exists "staff manage profiles" on public.profiles;
create policy "staff manage profiles" on public.profiles for all to authenticated using(public.current_role()='staff') with check(public.current_role()='staff');
drop policy if exists "read own or staff submissions" on public.submissions;
create policy "read own or staff submissions" on public.submissions for select to authenticated using(user_id=auth.uid() or public.current_role()='staff');
drop policy if exists "scholar insert own pending" on public.submissions;
create policy "scholar insert own pending" on public.submissions for insert to authenticated with check(user_id=auth.uid() and public.current_role()='scholar' and verification_status='Pending' and evaluation_status is null and renewal_status is null);
drop policy if exists "staff update submissions" on public.submissions;
create policy "staff update submissions" on public.submissions for update to authenticated using(public.current_role()='staff') with check(public.current_role()='staff');
drop policy if exists "read own or staff audit" on public.audit_history;
create policy "read own or staff audit" on public.audit_history for select to authenticated using(public.current_role()='staff' or exists(select 1 from public.submissions s where s.id=submission_id and s.user_id=auth.uid()));
-- No direct client writes to audit history; RPC functions insert audit rows.
revoke insert,update,delete on public.audit_history from authenticated;
create or replace function public.verify_submission(p_submission_id uuid,p_status text,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare s public.submissions%rowtype; begin
 if public.current_role() <> 'staff' then raise exception 'Only Scholarship Staff may verify evidence'; end if;
 if p_status not in ('Verified','Returned') then raise exception 'Invalid verification status'; end if;
 if p_status='Returned' and coalesce(trim(p_reason),'')='' then raise exception 'A return reason is required'; end if;
 select * into s from public.submissions where id=p_submission_id for update; if not found then raise exception 'Submission not found'; end if;
 update public.submissions set verification_status=p_status,verification_reason=case when p_status='Returned' then trim(p_reason) else null end,
 evaluation_status=null,evaluation_reasons=null,evaluated_at=null,renewal_status=null,decision_note=null,decided_by=null,decided_at=null where id=s.id;
 insert into public.audit_history(submission_id,action,old_value,new_value,note,actor) values(s.id,'verification',to_jsonb(s),jsonb_build_object('verification_status',p_status),p_reason,auth.uid());
end $$;
create or replace function public.evaluate_submission(p_submission_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.submissions%rowtype; p public.programs%rowtype; reasons text[]:='{}'; st text; begin
 if public.current_role() <> 'staff' then raise exception 'Only Scholarship Staff may evaluate submissions'; end if;
 select * into s from public.submissions where id=p_submission_id for update; if not found then raise exception 'Submission not found'; end if;
 if s.verification_status <> 'Verified' then raise exception 'Evaluation blocked: evidence must be Verified first'; end if;
 select * into p from public.programs where id=(select program_id from public.profiles where id=s.user_id);
 if s.gwa>p.max_gwa then reasons:=array_append(reasons,format('GWA %s exceeds maximum permitted %s',s.gwa,p.max_gwa)); end if;
 if s.units_enrolled<p.min_units then reasons:=array_append(reasons,format('Enrolled units %s is below minimum %s',s.units_enrolled,p.min_units)); end if;
 if s.failed_subjects>p.max_failed then reasons:=array_append(reasons,format('%s failed subject(s); maximum allowed is %s',s.failed_subjects,p.max_failed)); end if;
 if s.incomplete_grades>p.max_incomplete then reasons:=array_append(reasons,format('%s incomplete grade(s); maximum allowed is %s',s.incomplete_grades,p.max_incomplete)); end if;
 if s.dropped_subjects>p.max_dropped then reasons:=array_append(reasons,format('%s dropped subject(s); maximum allowed is %s',s.dropped_subjects,p.max_dropped)); end if;
 if s.submitted_at>p.deadline then reasons:=array_append(reasons,'Submission was after the deadline (2026-10-30 17:00 Asia/Manila)'); end if;
 st:=case when cardinality(reasons)=0 then 'Compliant' else 'With Deficiency' end;
 update public.submissions set evaluation_status=st,evaluation_reasons=array_to_string(reasons,'; '),evaluated_at=now(),renewal_status=null,decision_note=null,decided_by=null,decided_at=null where id=s.id;
 insert into public.audit_history(submission_id,action,old_value,new_value,note,actor) values(s.id,'evaluation',to_jsonb(s),jsonb_build_object('evaluation_status',st,'reasons',reasons),null,auth.uid());
 return jsonb_build_object('status',st,'reasons',array_to_string(reasons,'; '));
end $$;
create or replace function public.record_renewal_decision(p_submission_id uuid,p_status text,p_note text default '')
returns void language plpgsql security definer set search_path=public as $$
declare s public.submissions%rowtype; begin
 if public.current_role() <> 'staff' then raise exception 'Only Scholarship Staff may decide renewal'; end if;
 if p_status not in ('Approved','Held') then raise exception 'Invalid renewal decision'; end if;
 select * into s from public.submissions where id=p_submission_id for update; if not found then raise exception 'Submission not found'; end if;
 if s.verification_status<>'Verified' or s.evaluation_status is null then raise exception 'Renewal blocked until evidence is Verified and evaluation is complete'; end if;
 if p_status='Approved' and s.evaluation_status<>'Compliant' then raise exception 'Cannot approve a deficient record; choose Held'; end if;
 update public.submissions set renewal_status=p_status,decision_note=coalesce(trim(p_note),''),decided_by=auth.uid(),decided_at=now() where id=s.id;
 insert into public.audit_history(submission_id,action,old_value,new_value,note,actor) values(s.id,'renewal',to_jsonb(s),jsonb_build_object('renewal_status',p_status),p_note,auth.uid());
end $$;
grant execute on function public.verify_submission(uuid,text,text) to authenticated;
grant execute on function public.evaluate_submission(uuid) to authenticated;
grant execute on function public.record_renewal_decision(uuid,text,text) to authenticated;
-- View uses invoker permissions so RLS still applies.
create or replace view public.submission_overview with (security_invoker=true) as
select s.*, pr.student_id,pr.full_name,pr.program_id,pr.id as profile_id, pg.name as program_name
from public.submissions s join public.profiles pr on pr.id=s.user_id join public.programs pg on pg.id=pr.program_id;
-- Create the first staff user manually in Supabase Auth, then insert their profile using that Auth UUID:
-- insert into public.profiles(id,role,full_name) values ('AUTH-USER-UUID','staff','Scholarship Staff');
