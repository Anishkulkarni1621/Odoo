-- =====================================================================
-- Dayflow HRMS — Seed Data (for demo/testing)
-- Run AFTER schema.sql
-- =====================================================================

-- ---------------------------------------------------------------------
-- USERS (password_hash is a placeholder — bcrypt hash of "password123")
-- ---------------------------------------------------------------------
INSERT INTO users (employee_code, email, email_verified, password_hash, role) VALUES
('EMP-0001', 'admin@dayflow.com',    TRUE, '$2b$10$abcdefghijklmnopqrstuv', 'admin'),
('EMP-0002', 'priya.sharma@dayflow.com',  TRUE, '$2b$10$abcdefghijklmnopqrstuv', 'employee'),
('EMP-0003', 'rahul.verma@dayflow.com',   TRUE, '$2b$10$abcdefghijklmnopqrstuv', 'employee'),
('EMP-0004', 'ananya.iyer@dayflow.com',   TRUE, '$2b$10$abcdefghijklmnopqrstuv', 'employee'),
('EMP-0005', 'karan.mehta@dayflow.com',   TRUE, '$2b$10$abcdefghijklmnopqrstuv', 'employee'),
('EMP-0006', 'sneha.reddy@dayflow.com',   TRUE, '$2b$10$abcdefghijklmnopqrstuv', 'employee');

-- ---------------------------------------------------------------------
-- EMPLOYEE PROFILES
-- ---------------------------------------------------------------------
INSERT INTO employee_profiles
(user_id, first_name, last_name, phone_number, city, state, country, department, job_title, date_of_joining, manager_id)
VALUES
(1, 'Admin', 'User',      '9000000001', 'Bengaluru', 'Karnataka', 'India', 'HR',          'HR Officer',        '2023-01-10', NULL),
(2, 'Priya', 'Sharma',    '9000000002', 'Bengaluru', 'Karnataka', 'India', 'Engineering', 'Software Engineer', '2023-03-15', 1),
(3, 'Rahul', 'Verma',     '9000000003', 'Mumbai',    'Maharashtra','India','Engineering', 'Senior Engineer',   '2022-07-01', 1),
(4, 'Ananya','Iyer',      '9000000004', 'Chennai',   'Tamil Nadu','India', 'Design',      'UI/UX Designer',    '2023-05-20', 1),
(5, 'Karan', 'Mehta',     '9000000005', 'Delhi',     'Delhi',     'India', 'Sales',       'Sales Executive',   '2024-01-05', 1),
(6, 'Sneha', 'Reddy',     '9000000006', 'Hyderabad', 'Telangana', 'India', 'Marketing',   'Marketing Lead',    '2022-11-11', 1);

-- ---------------------------------------------------------------------
-- ATTENDANCE (last 5 days for each employee)
-- ---------------------------------------------------------------------
INSERT INTO attendance (user_id, attendance_date, check_in_time, check_out_time, status) VALUES
(2, CURRENT_DATE - 4, (CURRENT_DATE - 4) + TIME '09:05', (CURRENT_DATE - 4) + TIME '18:10', 'present'),
(2, CURRENT_DATE - 3, (CURRENT_DATE - 3) + TIME '09:00', (CURRENT_DATE - 3) + TIME '18:00', 'present'),
(2, CURRENT_DATE - 2, NULL, NULL, 'leave'),
(2, CURRENT_DATE - 1, (CURRENT_DATE - 1) + TIME '09:15', (CURRENT_DATE - 1) + TIME '13:00', 'half_day'),
(2, CURRENT_DATE,     (CURRENT_DATE) + TIME '09:02', NULL, 'present'),

(3, CURRENT_DATE - 4, (CURRENT_DATE - 4) + TIME '09:30', (CURRENT_DATE - 4) + TIME '18:30', 'present'),
(3, CURRENT_DATE - 3, NULL, NULL, 'absent'),
(3, CURRENT_DATE - 2, (CURRENT_DATE - 2) + TIME '09:10', (CURRENT_DATE - 2) + TIME '18:05', 'present'),
(3, CURRENT_DATE - 1, (CURRENT_DATE - 1) + TIME '09:00', (CURRENT_DATE - 1) + TIME '18:00', 'present'),
(3, CURRENT_DATE,     (CURRENT_DATE) + TIME '08:55', NULL, 'present'),

(4, CURRENT_DATE - 4, (CURRENT_DATE - 4) + TIME '10:00', (CURRENT_DATE - 4) + TIME '19:00', 'present'),
(4, CURRENT_DATE - 3, (CURRENT_DATE - 3) + TIME '09:45', (CURRENT_DATE - 3) + TIME '18:45', 'present'),
(4, CURRENT_DATE - 2, (CURRENT_DATE - 2) + TIME '09:40', (CURRENT_DATE - 2) + TIME '18:30', 'present'),
(4, CURRENT_DATE - 1, NULL, NULL, 'leave'),
(4, CURRENT_DATE,     (CURRENT_DATE) + TIME '09:50', NULL, 'present'),

(5, CURRENT_DATE - 4, (CURRENT_DATE - 4) + TIME '09:20', (CURRENT_DATE - 4) + TIME '18:15', 'present'),
(5, CURRENT_DATE - 3, (CURRENT_DATE - 3) + TIME '09:25', (CURRENT_DATE - 3) + TIME '18:20', 'present'),
(5, CURRENT_DATE - 2, (CURRENT_DATE - 2) + TIME '09:15', (CURRENT_DATE - 2) + TIME '18:10', 'present'),
(5, CURRENT_DATE - 1, (CURRENT_DATE - 1) + TIME '09:30', (CURRENT_DATE - 1) + TIME '18:00', 'present'),
(5, CURRENT_DATE,     (CURRENT_DATE) + TIME '09:05', NULL, 'present'),

(6, CURRENT_DATE - 4, NULL, NULL, 'absent'),
(6, CURRENT_DATE - 3, (CURRENT_DATE - 3) + TIME '09:00', (CURRENT_DATE - 3) + TIME '18:00', 'present'),
(6, CURRENT_DATE - 2, (CURRENT_DATE - 2) + TIME '09:00', (CURRENT_DATE - 2) + TIME '18:00', 'present'),
(6, CURRENT_DATE - 1, (CURRENT_DATE - 1) + TIME '09:00', (CURRENT_DATE - 1) + TIME '18:00', 'present'),
(6, CURRENT_DATE,     (CURRENT_DATE) + TIME '09:00', NULL, 'present');

-- ---------------------------------------------------------------------
-- LEAVE REQUESTS
-- ---------------------------------------------------------------------
INSERT INTO leave_requests (user_id, leave_type, start_date, end_date, employee_remarks, status, admin_comments, reviewed_by, reviewed_at) VALUES
(2, 'sick',   CURRENT_DATE - 2, CURRENT_DATE - 2, 'Fever, resting at home', 'approved', 'Get well soon', 1, NOW()),
(3, 'paid',   CURRENT_DATE + 5, CURRENT_DATE + 7, 'Family function', 'pending', NULL, NULL, NULL),
(4, 'unpaid', CURRENT_DATE - 1, CURRENT_DATE - 1, 'Personal emergency', 'approved', 'Approved, please inform in advance next time', 1, NOW()),
(5, 'paid',   CURRENT_DATE + 10, CURRENT_DATE + 12, 'Vacation', 'pending', NULL, NULL, NULL),
(6, 'sick',   CURRENT_DATE - 6, CURRENT_DATE - 5, 'Not feeling well', 'rejected', 'Insufficient leave balance', 1, NOW());

-- ---------------------------------------------------------------------
-- PAYROLL (current month)
-- ---------------------------------------------------------------------
INSERT INTO payroll (user_id, pay_period_start, pay_period_end, base_salary, bonus, deductions, tax_amount, payment_status, payment_date) VALUES
(2, date_trunc('month', CURRENT_DATE)::date, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::date, 65000, 2000, 1500, 6000, 'processed', CURRENT_DATE - 2),
(3, date_trunc('month', CURRENT_DATE)::date, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::date, 95000, 5000, 2000, 9000, 'processed', CURRENT_DATE - 2),
(4, date_trunc('month', CURRENT_DATE)::date, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::date, 55000, 0, 1000, 4500, 'processed', CURRENT_DATE - 2),
(5, date_trunc('month', CURRENT_DATE)::date, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::date, 45000, 3000, 500, 3800, 'pending', NULL),
(6, date_trunc('month', CURRENT_DATE)::date, (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::date, 70000, 1000, 1200, 6200, 'pending', NULL);
