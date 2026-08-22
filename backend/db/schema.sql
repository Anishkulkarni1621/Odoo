
-- Dayflow HRMS — PostgreSQL Schema
-- Author: Surya Rai

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE user_role AS ENUM ('admin', 'employee');

CREATE TYPE attendance_status AS ENUM ('present', 'absent', 'half_day', 'leave');

CREATE TYPE leave_type AS ENUM ('paid', 'sick', 'unpaid');

CREATE TYPE leave_status AS ENUM ('pending', 'approved', 'rejected');

-- 1. Users  (Authentication & Roles)

CREATE TABLE users (
    user_id         BIGSERIAL PRIMARY KEY,
    employee_code   VARCHAR(20)   NOT NULL UNIQUE,
    email           VARCHAR(255)  NOT NULL UNIQUE,
    email_verified  BOOLEAN       NOT NULL DEFAULT FALSE,
    password_hash   VARCHAR(255)  NOT NULL,
    role            user_role     NOT NULL DEFAULT 'employee',
    is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE users IS 'Core authentication and role table for all system users.';

CREATE INDEX idx_users_email        ON users (email);
CREATE INDEX idx_users_employee_code ON users (employee_code);
CREATE INDEX idx_users_role         ON users (role);

-- 2. Employee Profiles

CREATE TABLE employee_profiles (
    profile_id          BIGSERIAL PRIMARY KEY,
    user_id             BIGINT        NOT NULL UNIQUE
                            REFERENCES users (user_id) ON DELETE CASCADE,
    first_name          VARCHAR(100)  NOT NULL,
    last_name           VARCHAR(100)  NOT NULL,
    phone_number        VARCHAR(20),
    address_line1       VARCHAR(255),
    address_line2       VARCHAR(255),
    city                VARCHAR(100),
    state               VARCHAR(100),
    postal_code         VARCHAR(20),
    country             VARCHAR(100),
    profile_picture_url TEXT,
    department          VARCHAR(100),
    job_title            VARCHAR(150),
    date_of_joining     DATE,
    date_of_birth       DATE,
    manager_id          BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE employee_profiles IS 'Personal and job-related details, one-to-one with users.';

CREATE INDEX idx_employee_profiles_user_id     ON employee_profiles (user_id);
CREATE INDEX idx_employee_profiles_department  ON employee_profiles (department);
CREATE INDEX idx_employee_profiles_manager_id  ON employee_profiles (manager_id);


-- 3. Attendance Tracking

CREATE TABLE attendance (
    attendance_id   BIGSERIAL PRIMARY KEY,
    user_id         BIGINT              NOT NULL
                        REFERENCES users (user_id) ON DELETE CASCADE,
    attendance_date DATE                NOT NULL,
    check_in_time   TIMESTAMPTZ,
    check_out_time  TIMESTAMPTZ,
    status          attendance_status   NOT NULL DEFAULT 'present',
    notes           TEXT,
    created_at      TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ         NOT NULL DEFAULT NOW(),

    -- One attendance record per user per calendar day

    CONSTRAINT uq_attendance_user_date UNIQUE (user_id, attendance_date),
    -- Sanity check: check-out cannot precede check-in
    CONSTRAINT chk_attendance_times CHECK (
        check_out_time IS NULL OR check_in_time IS NULL OR check_out_time >= check_in_time
    )
);

COMMENT ON TABLE attendance IS 'Daily attendance records with check-in/out timestamps and status.';

CREATE INDEX idx_attendance_user_id ON attendance (user_id);
CREATE INDEX idx_attendance_date   ON attendance (attendance_date);
CREATE INDEX idx_attendance_user_date ON attendance (user_id, attendance_date);
CREATE INDEX idx_attendance_status ON attendance (status);


-- 4. Leave Management


CREATE TABLE leave_requests (
    leave_id          BIGSERIAL PRIMARY KEY,
    user_id           BIGINT        NOT NULL
                          REFERENCES users (user_id) ON DELETE CASCADE,
    leave_type        leave_type    NOT NULL,
    start_date        DATE          NOT NULL,
    end_date          DATE          NOT NULL,
    total_days        NUMERIC(5,1)  GENERATED ALWAYS AS (
                          (end_date - start_date) + 1
                      ) STORED,
    employee_remarks  TEXT,
    status            leave_status  NOT NULL DEFAULT 'pending',
    admin_comments    TEXT,
    reviewed_by       BIGINT REFERENCES users (user_id) ON DELETE SET NULL,
    reviewed_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_leave_dates CHECK (end_date >= start_date)
);

COMMENT ON TABLE leave_requests IS 'Employee time-off requests spanning a date range, with approval workflow.';

CREATE INDEX idx_leave_requests_user_id  ON leave_requests (user_id);
CREATE INDEX idx_leave_requests_status   ON leave_requests (status);
CREATE INDEX idx_leave_requests_dates    ON leave_requests (start_date, end_date);
CREATE INDEX idx_leave_requests_reviewed_by ON leave_requests (reviewed_by);

-- 5. Payroll and Salary Management

CREATE TABLE payroll (
    payroll_id        BIGSERIAL PRIMARY KEY,
    user_id           BIGINT         NOT NULL
                          REFERENCES users (user_id) ON DELETE CASCADE,
    pay_period_start  DATE           NOT NULL,
    pay_period_end    DATE           NOT NULL,
    base_salary       NUMERIC(12,2)  NOT NULL DEFAULT 0,
    bonus             NUMERIC(12,2)  NOT NULL DEFAULT 0,
    deductions        NUMERIC(12,2)  NOT NULL DEFAULT 0,
    tax_amount        NUMERIC(12,2)  NOT NULL DEFAULT 0,
    net_salary        NUMERIC(12,2)  GENERATED ALWAYS AS (
                          base_salary + bonus - deductions - tax_amount
                      ) STORED,
    payment_status    VARCHAR(20)    NOT NULL DEFAULT 'pending'
                          CHECK (payment_status IN ('pending', 'processed', 'failed')),
    payment_date      DATE,
    currency          VARCHAR(3)     NOT NULL DEFAULT 'USD',
    created_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ    NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_payroll_period CHECK (pay_period_end >= pay_period_start),
    CONSTRAINT uq_payroll_user_period UNIQUE (user_id, pay_period_start, pay_period_end)
);

COMMENT ON TABLE payroll IS 'Per-period salary structure and computed net pay for each employee.';

CREATE INDEX idx_payroll_user_id ON payroll (user_id);
CREATE INDEX idx_payroll_period  ON payroll (pay_period_start, pay_period_end);
CREATE INDEX idx_payroll_status  ON payroll (payment_status);


-- Auto-update updated_at trigger (applied to all tables with the column)

CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_users
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_employee_profiles
    BEFORE UPDATE ON employee_profiles
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_attendance
    BEFORE UPDATE ON attendance
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_leave_requests
    BEFORE UPDATE ON leave_requests
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_payroll
    BEFORE UPDATE ON payroll
    FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

