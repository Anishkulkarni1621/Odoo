-- Deletes all application data while preserving every table, type,
-- function, index, trigger, and constraint.
-- Run only when a completely empty database is required.

TRUNCATE TABLE
    attendance,
    attendance_corrections,
    attendance_monthly_summaries,
    employee_salary_structures,
    salary_structure_components,
    salary_structures,
    salary_components,
    employee_work_schedules,
    work_schedule_days,
    work_schedules,
    leave_attachments,
    leave_approval_history,
    leave_balances,
    leave_policies,
    leave_requests,
    employee_certifications,
    employee_skills,
    skills,
    employee_bank_details,
    employee_bios,
    employee_profiles,
    payroll,
    audit_logs,
    notifications,
    notification_preferences,
    users,
    companies,
    login_id_counters
RESTART IDENTITY CASCADE;
