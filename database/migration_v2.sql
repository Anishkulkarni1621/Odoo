-- Dayflow HRMS requirements migration
-- Additive and repeatable. Run after schema.sql.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$
BEGIN
    ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'hr_officer';
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS companies (
    company_id       BIGSERIAL PRIMARY KEY,
    company_name     VARCHAR(200) NOT NULL UNIQUE,
    logo_url         TEXT,
    email            VARCHAR(255),
    phone            VARCHAR(30),
    address_line1    VARCHAR(255),
    address_line2    VARCHAR(255),
    city             VARCHAR(100),
    state            VARCHAR(100),
    country          VARCHAR(100),
    is_active        BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE users ADD COLUMN IF NOT EXISTS company_id BIGINT REFERENCES companies(company_id) ON DELETE SET NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS login_id VARCHAR(40);
ALTER TABLE users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_changed_at TIMESTAMPTZ;
ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until TIMESTAMPTZ;
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_login_id ON users(login_id) WHERE login_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_company_id ON users(company_id);

INSERT INTO companies (company_name, email, country)
VALUES ('Dayflow Demo Company', 'admin@dayflow.com', 'India')
ON CONFLICT (company_name) DO NOTHING;

UPDATE users
SET company_id = (SELECT company_id FROM companies WHERE company_name = 'Dayflow Demo Company'),
    login_id = COALESCE(login_id, employee_code)
WHERE company_id IS NULL OR login_id IS NULL;

ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS employment_type VARCHAR(30) DEFAULT 'full_time';
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS employment_status VARCHAR(30) DEFAULT 'active';
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS work_location VARCHAR(150);
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS personal_email VARCHAR(255);
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS nationality VARCHAR(100);
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS gender VARCHAR(30);
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS marital_status VARCHAR(30);
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS emergency_contact_name VARCHAR(150);
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS emergency_contact_phone VARCHAR(30);
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS exit_date DATE;
ALTER TABLE employee_profiles ADD COLUMN IF NOT EXISTS exit_reason TEXT;

CREATE TABLE IF NOT EXISTS employee_bios (
    bio_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    about TEXT,
    interests TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS skills (
    skill_id BIGSERIAL PRIMARY KEY,
    skill_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS employee_skills (
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    skill_id BIGINT NOT NULL REFERENCES skills(skill_id) ON DELETE CASCADE,
    proficiency VARCHAR(30),
    PRIMARY KEY (user_id, skill_id)
);

CREATE TABLE IF NOT EXISTS employee_certifications (
    certification_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    certification_name VARCHAR(200) NOT NULL,
    issuing_organization VARCHAR(200),
    issue_date DATE,
    expiry_date DATE,
    credential_url TEXT
);

CREATE TABLE IF NOT EXISTS employee_bank_details (
    bank_detail_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users(user_id) ON DELETE CASCADE,
    account_holder_name VARCHAR(200),
    account_number VARCHAR(100),
    bank_name VARCHAR(150),
    ifsc_code VARCHAR(30),
    pan_number VARCHAR(30),
    uan_number VARCHAR(50),
    pf_number VARCHAR(50),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS salary_components (
    component_id BIGSERIAL PRIMARY KEY,
    company_id BIGINT REFERENCES companies(company_id) ON DELETE CASCADE,
    component_name VARCHAR(120) NOT NULL,
    component_code VARCHAR(50) NOT NULL,
    calculation_type VARCHAR(20) NOT NULL CHECK (calculation_type IN ('fixed', 'percentage')),
    percentage_of VARCHAR(50),
    is_deduction BOOLEAN NOT NULL DEFAULT FALSE,
    is_taxable BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE(company_id, component_code)
);

CREATE TABLE IF NOT EXISTS salary_structures (
    structure_id BIGSERIAL PRIMARY KEY,
    company_id BIGINT NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    structure_name VARCHAR(150) NOT NULL,
    wage_type VARCHAR(30) NOT NULL DEFAULT 'monthly',
    base_wage NUMERIC(12,2) NOT NULL DEFAULT 0,
    effective_from DATE NOT NULL,
    effective_to DATE,
    UNIQUE(company_id, structure_name, effective_from)
);

CREATE TABLE IF NOT EXISTS salary_structure_components (
    structure_id BIGINT NOT NULL REFERENCES salary_structures(structure_id) ON DELETE CASCADE,
    component_id BIGINT NOT NULL REFERENCES salary_components(component_id) ON DELETE CASCADE,
    value NUMERIC(12,2) NOT NULL DEFAULT 0,
    PRIMARY KEY(structure_id, component_id)
);

CREATE TABLE IF NOT EXISTS employee_salary_structures (
    assignment_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    structure_id BIGINT NOT NULL REFERENCES salary_structures(structure_id) ON DELETE RESTRICT,
    effective_from DATE NOT NULL,
    effective_to DATE,
    UNIQUE(user_id, effective_from)
);

CREATE TABLE IF NOT EXISTS work_schedules (
    schedule_id BIGSERIAL PRIMARY KEY,
    company_id BIGINT NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    schedule_name VARCHAR(120) NOT NULL,
    expected_hours NUMERIC(5,2) NOT NULL DEFAULT 8,
    break_minutes INTEGER NOT NULL DEFAULT 60,
    grace_minutes INTEGER NOT NULL DEFAULT 0,
    attendance_source VARCHAR(30) NOT NULL DEFAULT 'web',
    UNIQUE(company_id, schedule_name)
);

CREATE TABLE IF NOT EXISTS work_schedule_days (
    schedule_id BIGINT NOT NULL REFERENCES work_schedules(schedule_id) ON DELETE CASCADE,
    day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    is_working_day BOOLEAN NOT NULL DEFAULT TRUE,
    start_time TIME,
    end_time TIME,
    PRIMARY KEY(schedule_id, day_of_week)
);

CREATE TABLE IF NOT EXISTS employee_work_schedules (
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    schedule_id BIGINT NOT NULL REFERENCES work_schedules(schedule_id) ON DELETE RESTRICT,
    effective_from DATE NOT NULL,
    effective_to DATE,
    PRIMARY KEY(user_id, effective_from)
);

ALTER TABLE attendance ADD COLUMN IF NOT EXISTS work_minutes INTEGER;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS overtime_minutes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS late_minutes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS early_departure_minutes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS attendance_source VARCHAR(30) DEFAULT 'web';
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT TRUE;

CREATE TABLE IF NOT EXISTS attendance_corrections (
    correction_id BIGSERIAL PRIMARY KEY,
    attendance_id BIGINT NOT NULL REFERENCES attendance(attendance_id) ON DELETE CASCADE,
    requested_by BIGINT NOT NULL REFERENCES users(user_id),
    reviewed_by BIGINT REFERENCES users(user_id),
    requested_check_in TIMESTAMPTZ,
    requested_check_out TIMESTAMPTZ,
    reason TEXT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'approved', 'rejected')),
    reviewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS attendance_monthly_summaries (
    summary_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    month_start DATE NOT NULL,
    working_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    present_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    paid_leave_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    unpaid_leave_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    absent_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    payable_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    total_work_minutes INTEGER NOT NULL DEFAULT 0,
    total_overtime_minutes INTEGER NOT NULL DEFAULT 0,
    UNIQUE(user_id, month_start)
);

CREATE TABLE IF NOT EXISTS leave_policies (
    policy_id BIGSERIAL PRIMARY KEY,
    company_id BIGINT NOT NULL REFERENCES companies(company_id) ON DELETE CASCADE,
    leave_type leave_type NOT NULL,
    annual_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    carry_forward_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    requires_attachment BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE(company_id, leave_type)
);

CREATE TABLE IF NOT EXISTS leave_balances (
    balance_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    leave_type leave_type NOT NULL,
    calendar_year INTEGER NOT NULL,
    allocated_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    used_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    carried_days NUMERIC(5,1) NOT NULL DEFAULT 0,
    UNIQUE(user_id, leave_type, calendar_year)
);

ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS attachment_required BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;

CREATE TABLE IF NOT EXISTS leave_attachments (
    attachment_id BIGSERIAL PRIMARY KEY,
    leave_id BIGINT NOT NULL REFERENCES leave_requests(leave_id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    storage_key TEXT NOT NULL,
    mime_type VARCHAR(100),
    file_size BIGINT,
    uploaded_by BIGINT NOT NULL REFERENCES users(user_id),
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS leave_approval_history (
    history_id BIGSERIAL PRIMARY KEY,
    leave_id BIGINT NOT NULL REFERENCES leave_requests(leave_id) ON DELETE CASCADE,
    action VARCHAR(20) NOT NULL CHECK(action IN ('submitted', 'approved', 'rejected', 'cancelled')),
    acted_by BIGINT NOT NULL REFERENCES users(user_id),
    comments TEXT,
    acted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE payroll ADD COLUMN IF NOT EXISTS working_days NUMERIC(5,1) DEFAULT 0;
ALTER TABLE payroll ADD COLUMN IF NOT EXISTS payable_days NUMERIC(5,1) DEFAULT 0;
ALTER TABLE payroll ADD COLUMN IF NOT EXISTS unpaid_days NUMERIC(5,1) DEFAULT 0;
ALTER TABLE payroll ADD COLUMN IF NOT EXISTS overtime_amount NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE payroll ADD COLUMN IF NOT EXISTS loss_of_pay NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE payroll ADD COLUMN IF NOT EXISTS calculation_snapshot JSONB;

CREATE TABLE IF NOT EXISTS audit_logs (
    audit_id BIGSERIAL PRIMARY KEY,
    actor_user_id BIGINT REFERENCES users(user_id) ON DELETE SET NULL,
    action VARCHAR(80) NOT NULL,
    entity_type VARCHAR(80) NOT NULL,
    entity_id BIGINT,
    old_values JSONB,
    new_values JSONB,
    ip_address INET,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notifications (
    notification_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    notification_type VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notification_preferences (
    user_id BIGINT PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    email_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    in_app_enabled BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE OR REPLACE FUNCTION generate_employee_login_id(p_first_name TEXT, p_last_name TEXT, p_joining_date DATE)
RETURNS TEXT AS $$
DECLARE
    first_part TEXT := upper(left(regexp_replace(coalesce(p_first_name, ''), '[^A-Za-z]', '', 'g'), 2));
    last_part TEXT := upper(left(regexp_replace(coalesce(p_last_name, ''), '[^A-Za-z]', '', 'g'), 2));
    joining_year TEXT := to_char(coalesce(p_joining_date, CURRENT_DATE), 'YYYY');
    serial_no INTEGER;
BEGIN
    first_part := rpad(coalesce(NULLIF(first_part, ''), 'XX'), 2, 'X');
    last_part := rpad(coalesce(NULLIF(last_part, ''), 'XX'), 2, 'X');
    INSERT INTO login_id_counters(joining_year, last_serial)
    VALUES (joining_year::INTEGER, 1)
    ON CONFLICT (joining_year) DO UPDATE SET last_serial = login_id_counters.last_serial + 1
    RETURNING last_serial INTO serial_no;
    RETURN first_part || last_part || joining_year || lpad(serial_no::TEXT, 4, '0');
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS login_id_counters (
    joining_year INTEGER PRIMARY KEY,
    last_serial INTEGER NOT NULL DEFAULT 0
);

CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_companies') THEN
        CREATE TRIGGER set_updated_at_companies BEFORE UPDATE ON companies FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_employee_bios') THEN
        CREATE TRIGGER set_updated_at_employee_bios BEFORE UPDATE ON employee_bios FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_employee_bank_details') THEN
        CREATE TRIGGER set_updated_at_employee_bank_details BEFORE UPDATE ON employee_bank_details FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
    END IF;
END $$;
