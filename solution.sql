--task 1 Use COALESCE to display each student's nationality. If nationality is NULL, show 'Unknown'.
select concat (first_name,' ',last_name) , coalesce(nationality,'unknown')
from students

--task 2 Use NULLIF to treat a GPA of 0.0 as NULL. Show student name, their real GPA, and a cleaned version where 0.0 becomes NULL.
select concat (first_name,' ',last_name) , nullif(gpa,0.0)
from students

--task 3 Combine COALESCE + NULLIF: show each student's GPA. If GPA is NULL or 0.0, display 'Not Evaluated'.
select concat (first_name,' ',last_name) , coalesce(nullif(gpa,0.0)::text,'Not Evaluated') -- error if not casted
from students

--task 4 Create a temporary table temp_course_stats with: course_code, course_name, enrolled_count, avg_grade. Then find courses where avg_grade is above 75.

create temp table temp_course_stats as
select c.course_code , c.course_name , count(e.*) as enrolled_count , avg(e.grade) as avg_grade
from courses c
join enrollments e
on c.course_id = e.course_id
group by c.course_code , c.course_name
having avg(e.grade) >75 -- or make it all a subquery and use column name (avg_grade) instead of avg(e.grade)

select * from temp_course_stats

--task 5 Create a B-tree index on dept_id in the students table.
create index idx_students_dept_id on students(dept_id)

--task 6 Create a UNIQUE index on the email column of students. Then try to insert a duplicate email and observe the error.
create unique index idx_students_email on students(email)

insert into students  (first_name , last_name , email , gender, enroll_date)
select first_name , last_name , email , gender, enroll_date from students where student_id = 5 -- the error in the field being unique , not the index 
--if the field didnt have a unique constraint , then error would show index name , not constraint name

--task 7 Create a Partial index on salary in professors — only for active professors (is_active = TRUE

create index idx_professors_salary_active on professors (salary) where is_active = true


--viewing all indices
select indexname , indexdef from pg_indexes where tablename = 'professors'

--task 8 Create a view called v_student_details showing: student_id, full_name, email, gpa, dept_name, faculty_name. Query it to list students in dept_id = 3.

create or replace view v_student_details as 
select student_id, concat (first_name,' ',last_name) as full_name, email, gpa, d.dept_name, f.faculty_name 
from students s
join departments d
on s.dept_id = d.dept_id -- note : common field name require alias , thats why we need it here , not in email,gpa ..etc because they dont exist in more than 1 table
join faculties f
on f.faculty_id= d.faculty_id

select * from v_student_details where dept_id =3 -- incorrect , it doesnt know what dept_id is
--fix : 
select * from v_student_details where dept_name = (select dept_name from departments where dept_id = 3) -- it knows what dept_name is , because i project it in select query

--task 9 Create an audit table enrollment_audit. Then create a BEFORE UPDATE trigger on enrollments: if the grade changed, log old_grade, new_grade, student_id, changed_at, changed_by into the audit table.
--audit table search : An audit table is a specialized database table designed to track changes—insertions, updates, and deletions—made to a main "live" table.

-- select * from enrollments

--creating table
create table enrollment_audit (audit_id serial primary key ,old_grade numeric(4,2), new_grade numeric(4,2),
student_id integer references students(student_id), changed_at timestamptz, changed_by text ) -- in postgresql , we cant type foreign key inline, just references , or make a constraint and write foreign key inline
--                                                                           changed by can have a default value current_user
--trigger function
create or replace function log_enrollment ()
returns trigger
as $$
begin -- new variable is what we return in our trigger function, we can modify it -> new.changed_by
--also NEW refers to a row of the table the trigger is attached to: (enrollments , not enrollment_audit)
--
if new.grade is distinct from old.grade then -- this statement to avoid auditing useless updates that do'nt change anything
insert into enrollment_audit (old_grade , new_grade , student_id, changed_at , changed_by)
values 
(old.grade,
new.grade ,
old.student_id,
now(),
current_user);
end if;

-- new.changed_at = now(); --wrong , these are fields of the enrollment audit -> therefore to assign these values it must be in insert statement
-- new.changed_by = current_user;
--  -- what we can use new here for : changing something in enrollments itself , like grade_letter

return new;--necessary for a trigger function
end;
$$ language plpgsql


--creating trigger
create trigger trg_enrollments
before update on enrollments
for each row 
execute function log_enrollment();--don't forget ()



--task 10 Test the grade trigger: update the grade of enrollment_id = 1. Verify the audit log was written. Then update again with the SAME grade and confirm no new audit row.

update enrollments set grade = 43 where enrollment_id = 2

select * from enrollment_audit

--task 11 Create a BEFORE INSERT trigger on professors: if salary is NULL or below 5000, set it to 5000 automatically.
--trigger function

create or replace function ensure_salary ()
returns trigger
as $$
begin
if new.salary is null or new.salary <5000 then
new.salary = 5000 ;
end if ; 
return new;
end;
$$ language plpgsql

--trigger
create trigger trg_salary
before insert on professors
for each row
execute function ensure_salary();

--insert statement 
insert into professors (first_name,last_name,email,salary)
values ('moamen','soltan','moamensoltan@gmail.com',0)

insert into professors (first_name,last_name,email,salary)
values ('moamen','soltan','moamensosltan@gmail.com',null)

select * from professors 

--task 12 Run a transaction that: (1) increases all professor salaries in dept_id=1 by 10%, (2) inserts a log record into a salary_log table. Verify both changes then COMMIT.
--table
CREATE TABLE IF NOT EXISTS salary_log 
( log_id SERIAL PRIMARY KEY, prof_id INTEGER, old_salary NUMERIC, new_salary NUMERIC,
changed_by TEXT DEFAULT CURRENT_USER, changed_at TIMESTAMPTZ DEFAULT NOW() );

--transaction note : to fix transaction aborted issue -> run rollback alone

-- use triggers or CTE's to view old data 

BEGIN;--transaction began

WITH updated AS (
    UPDATE professors
    SET salary = salary * 1.1
    WHERE dept_id = 1
    RETURNING 
        prof_id,
        salary / 1.1 AS old_salary,
        salary AS new_salary
)
INSERT INTO salary_log (prof_id, old_salary, new_salary)
SELECT prof_id, old_salary, new_salary
FROM updated;

-- verifying
SELECT * FROM professors WHERE dept_id = 1;
SELECT * FROM salary_log;

COMMIT;--here transaction ended

--task 13 Demonstrate ROLLBACK: delete all enrollments for student_id=1 inside a transaction, then ROLLBACK. Confirm the rows are still there.

BEGIN;--transaction began


DELETE FROM enrollments -- NEVER run each query independently without begin , begin means its a transaction
WHERE student_id = 1;


SELECT * FROM enrollments
WHERE student_id = 1;


ROLLBACK; -- here tranasaction ended  -> run query from here


SELECT * FROM enrollments
WHERE student_id = 1;


--task 14

BEGIN; --transaction strat


UPDATE faculties
SET budget = budget + 500000
WHERE faculty_id = 1;


SAVEPOINT sp1;


UPDATE faculties
SET budget = budget + 500000
WHERE faculty_id = 2;


ROLLBACK TO SAVEPOINT sp1;


COMMIT; -- transaction end


SELECT * FROM faculties WHERE faculty_id IN (1, 2);


-- task 15 Test SET ROLE: as registrar_user (readwrite), switch to uni_readonly only. Try a SELECT (should work) and an INSERT (should fail). Then RESET ROLE.

--creating user
create user registrar_user with password '1234';

--creating role
create role uni_readonly;



--assigning privileges to role
grant select on all tables in schema public to uni_readonly;


--assigning a role to user
grant uni_readonly to registrar_user

--to try , logout as postgres , and login as registrar_user
set role uni_readonly

select * from professors -- works

insert into professors (first_name,last_name,email,salary)
values ('moamen','soltan','moamensosltan@gmail.com',null) -- permission denied


--reset role 

reset role;


--task 16 

--create user
create user student_portal with password '1234'

--creating role

create role uni_redwrite;

--assigning privileges to role

grant select , insert , update , delete on all tables in schema public to uni_redwrite;

--assigning role to user 

grant uni_redwrite to student_portal


--revoking delete on employees on a certain table
revoke delete on students from uni_redwrite

--verify
set role uni_redwrite

delete from students -- permission denied

reset role -- dont forget

-- remove all privileges from role
revoke all privileges on all tables in schema public from uni_redwrite ; 

--or specific table
revoke all privileges on students from uni_redwrite ; 

--removing user from a role 
revoke uni_redwrite from student_portal;