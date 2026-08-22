import os
import logging
from pathlib import Path
from decimal import Decimal
from uuid import uuid4

import bcrypt
import psycopg
from dotenv import load_dotenv
from flask import Flask, jsonify, redirect, request, send_from_directory, session
from werkzeug.utils import secure_filename


PROJECT_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(Path(__file__).resolve().parent / ".env")

PAGES_DIR = PROJECT_ROOT / "pages"
LOGIN_PAGE_DIR = PAGES_DIR / "login" / "page"
LOGIN_CSS_DIR = PAGES_DIR / "login" / "css"
LOGIN_JS_DIR = PAGES_DIR / "login" / "js"
UPLOAD_DIR = PROJECT_ROOT / "uploads" / "logos"
DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not configured. Copy backend/.env.example to backend/.env.")

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "development-only-change-this-secret")
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")
app.config["MAX_CONTENT_LENGTH"] = 4 * 1024 * 1024
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
ALLOWED_LOGO_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp", "svg"}
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(name)s | %(message)s",
)
app.logger.setLevel(logging.INFO)
ACTIVE_SESSIONS = {}


@app.before_request
def log_request_start():
    app.logger.info("REQUEST %s %s", request.method, request.path)


@app.after_request
def log_request_end(response):
    app.logger.info("RESPONSE %s %s -> %s", request.method, request.path, response.status_code)
    return response


def log_database(operation, detail=""):
    app.logger.info("DATABASE %s%s", operation, f" | {detail}" if detail else "")


def get_connection():
    log_database("CONNECT", "opening PostgreSQL connection")
    return psycopg.connect(DATABASE_URL)


REQUIRED_TABLES = {
    "users", "employee_profiles", "companies", "employee_bios", "employee_skills",
    "employee_certifications", "employee_bank_details", "salary_components",
    "salary_structures", "salary_structure_components", "employee_salary_structures",
    "work_schedules", "work_schedule_days", "employee_work_schedules", "attendance",
    "attendance_corrections", "attendance_monthly_summaries", "leave_policies",
    "leave_balances", "leave_requests", "leave_attachments", "leave_approval_history",
    "payroll", "audit_logs", "notifications", "notification_preferences",
}


def verify_database(connection):
    log_database("VERIFY START", f"checking {len(REQUIRED_TABLES)} required tables")
    with connection.cursor() as cursor:
        cursor.execute(
            "SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename = ANY(%s)",
            (list(REQUIRED_TABLES),),
        )
        existing_tables = {row[0] for row in cursor.fetchall()}
        missing_tables = sorted(REQUIRED_TABLES - existing_tables)

        required_columns = {
            "users": {"company_id", "login_id", "must_change_password"},
            "employee_profiles": {"personal_email", "nationality", "gender", "marital_status"},
            "attendance": {"work_minutes", "overtime_minutes", "attendance_source"},
            "payroll": {"payable_days", "unpaid_days", "calculation_snapshot"},
        }
        missing_columns = {}
        for table, columns in required_columns.items():
            if table not in existing_tables:
                missing_columns[table] = sorted(columns)
                continue
            cursor.execute(
                """
                SELECT column_name FROM information_schema.columns
                WHERE table_schema = 'public' AND table_name = %s AND column_name = ANY(%s)
                """,
                (table, list(columns)),
            )
            found = {row[0] for row in cursor.fetchall()}
            if found != columns:
                missing_columns[table] = sorted(columns - found)

    result = {
        "ok": not missing_tables and not missing_columns,
        "missingTables": missing_tables,
        "missingColumns": missing_columns,
    }
    log_database(
        "VERIFY COMPLETE",
        f"ok={result['ok']} missing_tables={len(missing_tables)} missing_column_groups={len(missing_columns)}",
    )
    return result


@app.get("/")
def index():
    return redirect("/signin")


@app.get("/signin")
def signin_page():
    return redirect("/login/page/signin.html")


@app.get("/signup")
def signup_page():
    return redirect("/login/page/signup.html")


@app.get("/login/page/<page_name>")
def login_page_asset(page_name):
    if page_name not in {"signin.html", "signup.html"}:
        return jsonify({"error": "Page not found"}), 404
    return send_from_directory(LOGIN_PAGE_DIR, page_name)


@app.get("/login/css/<path:asset_name>")
def login_css_asset(asset_name):
    return send_from_directory(LOGIN_CSS_DIR, asset_name)


@app.get("/login/js/<path:asset_name>")
def login_js_asset(asset_name):
    return send_from_directory(LOGIN_JS_DIR, asset_name)


@app.get("/uploads/logos/<path:file_name>")
def company_logo(file_name):
    return send_from_directory(UPLOAD_DIR, file_name)


PORTAL_GROUPS = {
    "employee": {"emp_dashboard.html", "employee_profile.html", "private_information.html", "resume.html", "salary.html", "leave_application.html", "attendance.html", "notifications.html", "update_password.html"},
    "hr": {"HR_dashboard.html", "HR_emp_page.html", "hr_emps_attendance.html", "HR_leaves_app.html", "add_employee.html", "salary_management.html", "leave_allocation.html", "company_settings.html", "attendance_corrections.html", "notifications.html"},
}


@app.get("/pages/<group>/<page_name>")
def portal_page(group, page_name):
    if group not in PORTAL_GROUPS or page_name not in PORTAL_GROUPS[group]:
        return jsonify({"error": "Page not found"}), 404
    return send_from_directory(PAGES_DIR / group, page_name)


@app.get("/pages/<page_name>")
def old_portal_page_url(page_name):
    for group, pages in PORTAL_GROUPS.items():
        if page_name in pages:
            return redirect(f"/pages/{group}/{page_name}", code=308)
    return jsonify({"error": "Page not found"}), 404


@app.get("/css/<path:asset_name>")
def portal_css_asset(asset_name):
    return send_from_directory(PAGES_DIR / "css", asset_name)


@app.get("/pages/css/<path:asset_name>")
def nested_portal_css_asset(asset_name):
    return send_from_directory(PAGES_DIR / "css", asset_name)


@app.get("/js/<path:asset_name>")
def portal_js_asset(asset_name):
    return send_from_directory(PAGES_DIR / "js", asset_name)


@app.get("/pages/js/<path:asset_name>")
def nested_portal_js_asset(asset_name):
    return send_from_directory(PAGES_DIR / "js", asset_name)


def current_user_id():
    token = request.headers.get("X-Session-Token")
    if token:
        return ACTIVE_SESSIONS.get(token, {}).get("user_id")
    return session.get("user_id")


def current_user_role():
    token = request.headers.get("X-Session-Token")
    if token:
        return ACTIVE_SESSIONS.get(token, {}).get("role")
    return session.get("role")


def require_session():
    user_id = current_user_id()
    if not user_id:
        return None, (jsonify({"error": "Authentication required"}), 401)
    return user_id, None


def require_hr_session():
    user_id, error = require_session()
    if error:
        return None, error
    if current_user_role() not in {"admin", "hr_officer"}:
        return None, (jsonify({"error": "Admin or HR Officer access required"}), 403)
    return user_id, None


def rows_as_dicts(cursor):
    columns = [column.name for column in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def json_value(value):
    if hasattr(value, "isoformat"):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    return value


def json_rows(rows):
    return [{key: json_value(value) for key, value in row.items()} for row in rows]


@app.get("/api/employees")
def employees():
    _, error = require_hr_session()
    if error:
        return error
    search = (request.args.get("search") or "").strip()
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", "employee directory")
            cursor.execute(
                """
                SELECT u.user_id, COALESCE(u.login_id, u.employee_code) AS login_id,
                       u.email, u.role, p.first_name, p.last_name, p.department,
                       p.job_title, p.profile_picture_url, p.employment_status
                FROM users u JOIN employee_profiles p ON p.user_id = u.user_id
                WHERE u.is_active AND (%s = '' OR CONCAT_WS(' ', p.first_name, p.last_name, u.email, p.department) ILIKE %s)
                ORDER BY p.first_name, p.last_name
                """,
                (search, f"%{search}%"),
            )
            return jsonify({"employees": json_rows(rows_as_dicts(cursor))})


@app.get("/api/employees/<int:user_id>")
def employee_profile(user_id):
    viewer_id, error = require_session()
    if error:
        return error
    if current_user_role() == "employee" and viewer_id != user_id:
        return jsonify({"error": "Employees can access only their own profile"}), 403
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", f"employee profile user_id={user_id}")
            cursor.execute(
                """
                SELECT u.user_id, u.email, u.role, COALESCE(u.login_id, u.employee_code) AS login_id,
                       c.company_name, c.logo_url, p.*, b.about, b.interests
                FROM users u
                LEFT JOIN companies c ON c.company_id = u.company_id
                LEFT JOIN employee_profiles p ON p.user_id = u.user_id
                LEFT JOIN employee_bios b ON b.user_id = u.user_id
                WHERE u.user_id = %s
                """,
                (user_id,),
            )
            profile = cursor.fetchone()
            if not profile:
                return jsonify({"error": "Employee not found"}), 404
            columns = [column.name for column in cursor.description]
            return jsonify({"employee": {key: json_value(value) for key, value in zip(columns, profile)}})


@app.patch("/api/profile")
def update_profile():
    user_id, error = require_session()
    if error:
        return error
    payload = request.get_json(silent=True) or request.form
    profile_fields = {
        "phone_number": payload.get("phone_number"), "address_line1": payload.get("address_line1"),
        "nationality": payload.get("nationality"), "gender": payload.get("gender"),
        "marital_status": payload.get("marital_status"),
    }
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("UPDATE", f"employee profile user_id={user_id}")
            cursor.execute("""UPDATE employee_profiles SET phone_number=%s, address_line1=%s,
                              nationality=%s, gender=%s, marital_status=%s, updated_at=NOW()
                              WHERE user_id=%s""", (*profile_fields.values(), user_id))
            about = payload.get("about")
            interests = payload.get("interests")
            if about is not None or interests is not None:
                cursor.execute("""INSERT INTO employee_bios(user_id, about, interests) VALUES (%s,%s,%s)
                                  ON CONFLICT(user_id) DO UPDATE SET about=COALESCE(EXCLUDED.about, employee_bios.about),
                                  interests=COALESCE(EXCLUDED.interests, employee_bios.interests), updated_at=NOW()""", (user_id, about, interests))
            return jsonify({"message": "Profile details saved"})


@app.get("/api/dashboard/employee")
def employee_dashboard():
    user_id, error = require_session()
    if error:
        return error
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", f"employee dashboard user_id={user_id}")
            cursor.execute("SELECT attendance_date, check_in_time, check_out_time, status, work_minutes, overtime_minutes FROM attendance WHERE user_id=%s ORDER BY attendance_date DESC LIMIT 10", (user_id,))
            attendance_rows = json_rows(rows_as_dicts(cursor))
            cursor.execute("SELECT leave_type, allocated_days, used_days, carried_days, allocated_days + carried_days - used_days AS remaining_days FROM leave_balances WHERE user_id=%s AND calendar_year=EXTRACT(YEAR FROM CURRENT_DATE)::int", (user_id,))
            balances = json_rows(rows_as_dicts(cursor))
            cursor.execute("SELECT COUNT(*) AS total, COUNT(*) FILTER (WHERE status='pending') AS pending FROM leave_requests WHERE user_id=%s", (user_id,))
            leave_summary = rows_as_dicts(cursor)[0]
    return jsonify({"userId": user_id, "attendance": attendance_rows, "leaveBalances": balances, "leaveSummary": leave_summary})


@app.get("/api/dashboard/hr")
def hr_dashboard():
    _, error = require_hr_session()
    if error:
        return error
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", "HR dashboard summary")
            cursor.execute("SELECT COUNT(*) AS employee_count FROM users WHERE is_active AND role <> 'admin'")
            employee_count = rows_as_dicts(cursor)[0]
            cursor.execute("SELECT COUNT(*) AS pending_leave_count FROM leave_requests WHERE status='pending'")
            pending_leave_count = rows_as_dicts(cursor)[0]
            cursor.execute("SELECT status, COUNT(*) AS count FROM attendance WHERE attendance_date=CURRENT_DATE GROUP BY status ORDER BY status")
            attendance_summary = json_rows(rows_as_dicts(cursor))
            cursor.execute("SELECT leave_id, user_id, leave_type, start_date, end_date, employee_remarks, status FROM leave_requests WHERE status='pending' ORDER BY created_at DESC LIMIT 20")
            pending_leaves = json_rows(rows_as_dicts(cursor))
    return jsonify({"employees": employee_count, "pendingLeaves": pending_leave_count, "attendance": attendance_summary, "leaveRequests": pending_leaves})


@app.get("/api/attendance")
def attendance_list():
    viewer_id, error = require_session()
    if error:
        return error
    requested_id = request.args.get("user_id")
    user_id = requested_id if current_user_role() in {"admin", "hr_officer"} else viewer_id
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", "attendance records")
            if user_id:
                cursor.execute("SELECT a.*, CONCAT_WS(' ', p.first_name, p.last_name) AS employee_name FROM attendance a JOIN employee_profiles p ON p.user_id=a.user_id WHERE a.user_id=%s ORDER BY attendance_date DESC LIMIT 100", (int(user_id),))
            else:
                cursor.execute("SELECT a.*, CONCAT_WS(' ', p.first_name, p.last_name) AS employee_name FROM attendance a JOIN employee_profiles p ON p.user_id=a.user_id ORDER BY attendance_date DESC LIMIT 100")
            return jsonify({"attendance": json_rows(rows_as_dicts(cursor))})


@app.post("/api/attendance/check-in")
def check_in():
    user_id, error = require_session()
    if error:
        return error
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("INSERT/UPDATE", f"attendance check-in user_id={user_id}")
            cursor.execute("""INSERT INTO attendance(user_id, attendance_date, check_in_time, status)
                              VALUES (%s, CURRENT_DATE, NOW(), 'present')
                              ON CONFLICT(user_id, attendance_date) DO UPDATE SET check_in_time=COALESCE(attendance.check_in_time, EXCLUDED.check_in_time), status='present'
                              RETURNING attendance_id, attendance_date, check_in_time, status""", (user_id,))
            row = cursor.fetchone()
            return jsonify({"attendance": {"attendanceId": row[0], "date": json_value(row[1]), "checkIn": json_value(row[2]), "status": row[3]}})


@app.post("/api/attendance/check-out")
def check_out():
    user_id, error = require_session()
    if error:
        return error
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("UPDATE", f"attendance check-out user_id={user_id}")
            cursor.execute("""UPDATE attendance SET check_out_time=NOW(), work_minutes=GREATEST(0, EXTRACT(EPOCH FROM (NOW()-check_in_time))/60)::int
                              WHERE user_id=%s AND attendance_date=CURRENT_DATE RETURNING attendance_id, check_out_time, work_minutes""", (user_id,))
            row = cursor.fetchone()
            if not row:
                return jsonify({"error": "Check in before checking out"}), 400
            return jsonify({"attendanceId": row[0], "checkOut": json_value(row[1]), "workMinutes": row[2]})


@app.get("/api/leave-balances")
def leave_balances():
    user_id, error = require_session()
    if error:
        return error
    if current_user_role() in {"admin", "hr_officer"} and request.args.get("user_id"):
        user_id = int(request.args["user_id"])
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", f"leave balances user_id={user_id}")
            cursor.execute("SELECT leave_type, allocated_days, used_days, carried_days, allocated_days + carried_days - used_days AS remaining_days FROM leave_balances WHERE user_id=%s ORDER BY leave_type", (int(user_id),))
            return jsonify({"balances": json_rows(rows_as_dicts(cursor))})


@app.post("/api/leave-balances")
def create_leave_balance():
    _, error = require_hr_session()
    if error:
        return error
    payload = request.get_json(silent=True) or request.form
    required = [payload.get("employee_id"), payload.get("leave_type"), payload.get("calendar_year"), payload.get("allocated_days")]
    if any(value in (None, "") for value in required):
        return jsonify({"error": "Employee, leave type, year, and allocated days are required"}), 400
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("INSERT/UPDATE", "leave balance allocation")
            cursor.execute("""INSERT INTO leave_balances(user_id, leave_type, calendar_year, allocated_days)
                              VALUES (%s, %s, %s, %s)
                              ON CONFLICT(user_id, leave_type, calendar_year) DO UPDATE SET allocated_days=EXCLUDED.allocated_days
                              RETURNING balance_id""", (int(payload["employee_id"]), payload["leave_type"], int(payload["calendar_year"]), payload["allocated_days"]))
            return jsonify({"message": "Leave allocation saved", "balanceId": cursor.fetchone()[0]}), 201


@app.post("/api/company")
def update_company():
    user_id, error = require_hr_session()
    if error:
        return error
    payload = request.get_json(silent=True) or request.form
    logo_file = request.files.get("company_logo")
    logo_url = None
    if logo_file and logo_file.filename:
        filename = secure_filename(logo_file.filename)
        extension = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        if extension not in ALLOWED_LOGO_EXTENSIONS:
            return jsonify({"error": "Logo must be PNG, JPG, JPEG, GIF, WEBP, or SVG"}), 400
        stored_name = f"company-{uuid4().hex}.{extension}"
        logo_file.save(UPLOAD_DIR / stored_name)
        logo_url = f"/uploads/logos/{stored_name}"
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT company_id FROM users WHERE user_id=%s", (user_id,))
            company = cursor.fetchone()
            if not company:
                return jsonify({"error": "Company not found"}), 404
            log_database("UPDATE", f"company settings company_id={company[0]}")
            cursor.execute("""UPDATE companies SET company_name=COALESCE(NULLIF(%s,''), company_name), email=%s,
                              phone=%s, country=%s, address_line1=%s,
                              logo_url=COALESCE(%s, logo_url), updated_at=NOW() WHERE company_id=%s""", (payload.get("company_name"), payload.get("email") or None, payload.get("phone") or None, payload.get("country") or None, payload.get("address_line1") or None, logo_url, company[0]))
    return jsonify({"message": "Company settings saved", "logoUrl": logo_url})


@app.post("/api/salary/components")
def create_salary_component():
    user_id, error = require_hr_session()
    if error:
        return error
    payload = request.get_json(silent=True) or request.form
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute("SELECT company_id FROM users WHERE user_id=%s", (user_id,))
            company = cursor.fetchone()
            if not company:
                return jsonify({"error": "Company not found"}), 404
            log_database("INSERT", "salary component")
            cursor.execute("""INSERT INTO salary_components(company_id, component_name, component_code, calculation_type, percentage_of)
                              VALUES (%s, %s, %s, %s, %s) RETURNING component_id""", (company[0], payload.get("component_name"), payload.get("component_code"), payload.get("calculation_type") or "fixed", payload.get("percentage_of") or None))
            return jsonify({"message": "Salary component saved", "componentId": cursor.fetchone()[0]}), 201


@app.get("/api/notifications")
def notifications():
    user_id, error = require_session()
    if error:
        return error
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", f"notifications user_id={user_id}")
            cursor.execute("SELECT notification_id, notification_type, title, message, is_read, created_at FROM notifications WHERE user_id=%s ORDER BY created_at DESC LIMIT 50", (user_id,))
            return jsonify({"notifications": json_rows(rows_as_dicts(cursor))})


@app.get("/api/attendance/corrections")
def attendance_corrections():
    _, error = require_hr_session()
    if error:
        return error
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", "attendance corrections")
            cursor.execute("""SELECT c.correction_id, c.attendance_id, c.requested_by, c.reason, c.status, c.created_at,
                              CONCAT_WS(' ', p.first_name, p.last_name) AS employee_name
                              FROM attendance_corrections c JOIN employee_profiles p ON p.user_id=c.requested_by
                              WHERE c.status='pending' ORDER BY c.created_at DESC""")
            return jsonify({"corrections": json_rows(rows_as_dicts(cursor))})


@app.route("/api/leaves", methods=["GET", "POST"])
def leaves():
    if request.method == "GET":
        viewer_id, error = require_session()
        if error:
            return error
        user_id = request.args.get("user_id") if current_user_role() in {"admin", "hr_officer"} else viewer_id
        with get_connection() as connection:
            with connection.cursor() as cursor:
                log_database("FETCH", "leave requests")
                query = "SELECT l.*, CONCAT_WS(' ', p.first_name, p.last_name) AS employee_name FROM leave_requests l JOIN employee_profiles p ON p.user_id=l.user_id"
                if user_id:
                    query += " WHERE l.user_id=%s"
                    cursor.execute(query + " ORDER BY l.created_at DESC", (int(user_id),))
                else:
                    cursor.execute(query + " ORDER BY l.created_at DESC")
                return jsonify({"leaves": json_rows(rows_as_dicts(cursor))})

    payload = request.get_json(silent=True) or request.form
    user_id, error = require_session()
    if error:
        return error
    if not user_id or not payload.get("leave_type") or not payload.get("start_date") or not payload.get("end_date"):
        return jsonify({"error": "leave_type, start_date, and end_date are required"}), 400
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("INSERT", f"leave request user_id={user_id}")
            cursor.execute("""INSERT INTO leave_requests(user_id, leave_type, start_date, end_date, employee_remarks)
                              VALUES (%s, %s, %s, %s, %s) RETURNING leave_id, status""", (int(user_id), payload["leave_type"], payload["start_date"], payload["end_date"], payload.get("remarks")))
            row = cursor.fetchone()
            return jsonify({"leaveId": row[0], "status": row[1]}), 201


@app.patch("/api/leaves/<int:leave_id>")
def update_leave(leave_id):
    reviewer_id, error = require_hr_session()
    if error:
        return error
    payload = request.get_json(silent=True) or {}
    status = payload.get("status")
    if status not in {"approved", "rejected", "cancelled"} or not reviewer_id:
        return jsonify({"error": "A valid status and reviewer ID are required"}), 400
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("UPDATE", f"leave approval leave_id={leave_id} status={status}")
            cursor.execute("UPDATE leave_requests SET status=%s, admin_comments=%s, reviewed_by=%s, reviewed_at=NOW() WHERE leave_id=%s RETURNING leave_id, status", (status, payload.get("comments"), int(reviewer_id), leave_id))
            row = cursor.fetchone()
            if not row:
                return jsonify({"error": "Leave request not found"}), 404
            cursor.execute("INSERT INTO leave_approval_history(leave_id, action, acted_by, comments) VALUES (%s, %s, %s, %s)", (leave_id, status, int(reviewer_id), payload.get("comments")))
            return jsonify({"leaveId": row[0], "status": row[1]})


@app.get("/api/health")
def health():
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                log_database("FETCH", "health check SELECT 1")
                cursor.execute("SELECT 1")
            verification = verify_database(connection)
        status_code = 200 if verification["ok"] else 503
        return jsonify({"status": "ok" if verification["ok"] else "migration_required", "database": "connected", "schema": verification}), status_code
    except psycopg.Error as error:
        log_database("ERROR", f"health check failed: {error}")
        return jsonify({"status": "error", "database": "unavailable", "detail": str(error)}), 503


@app.get("/api/database/verify")
def database_verify():
    try:
        with get_connection() as connection:
            result = verify_database(connection)
        return jsonify(result), 200 if result["ok"] else 503
    except psycopg.Error as error:
        log_database("ERROR", f"verification failed: {error}")
        return jsonify({"ok": False, "error": str(error)}), 503


@app.post("/api/auth/signup")
def signup():
    payload = request.get_json(silent=True) or request.form
    company_name = (payload.get("companyName") or "").strip()
    first_name = (payload.get("name") or payload.get("fullName") or payload.get("firstName") or "").strip()
    email = (payload.get("email") or "").strip().lower()
    phone = (payload.get("phone") or "").strip()
    password = payload.get("password") or ""
    logo_file = request.files.get("logoFile")

    if not all((company_name, first_name, email, password)):
        return jsonify({"error": "Company name, name, email, and password are required"}), 400
    if len(password) < 8:
        return jsonify({"error": "Password must contain at least 8 characters"}), 400

    name_parts = first_name.split(maxsplit=1)
    given_name = name_parts[0]
    family_name = name_parts[1] if len(name_parts) > 1 else "User"
    password_hash = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()

    logo_url = None
    if logo_file and logo_file.filename:
        original_name = secure_filename(logo_file.filename)
        extension = original_name.rsplit(".", 1)[-1].lower() if "." in original_name else ""
        if extension not in ALLOWED_LOGO_EXTENSIONS:
            return jsonify({"error": "Logo must be a PNG, JPG, GIF, WEBP, or SVG image"}), 400
        stored_name = f"{uuid4().hex}.{extension}"
        logo_file.save(UPLOAD_DIR / stored_name)
        logo_url = f"/uploads/logos/{stored_name}"

    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                log_database("FETCH", "company lookup/create")
                cursor.execute(
                    """
                    INSERT INTO companies (company_name, logo_url) VALUES (%s, %s)
                    ON CONFLICT (company_name) DO UPDATE SET logo_url = COALESCE(EXCLUDED.logo_url, companies.logo_url)
                    RETURNING company_id
                    """,
                    (company_name, logo_url),
                )
                company_id = cursor.fetchone()[0]
                log_database("FETCH", "generated Login ID")
                cursor.execute("SELECT generate_employee_login_id(%s, %s, CURRENT_DATE)", (given_name, family_name))
                login_id = cursor.fetchone()[0]
                log_database("INSERT", "new user and employee profile")
                cursor.execute(
                    """
                    INSERT INTO users (company_id, employee_code, login_id, email, password_hash, role,
                                       email_verified, must_change_password, password_changed_at)
                    VALUES (%s, %s, %s, %s, %s, 'hr_officer', FALSE, FALSE, NOW())
                    RETURNING user_id
                    """,
                    (company_id, login_id, login_id, email, password_hash),
                )
                user_id = cursor.fetchone()[0]
                cursor.execute(
                    """INSERT INTO employee_profiles (user_id, first_name, last_name, phone_number, date_of_joining)
                       VALUES (%s, %s, %s, %s, CURRENT_DATE)""",
                    (user_id, given_name, family_name, phone or None),
                )
        return jsonify({"message": "Account created", "userId": user_id, "role": "hr_officer", "loginId": login_id}), 201
    except psycopg.errors.UniqueViolation:
        log_database("ERROR", "signup conflict: duplicate email or account details")
        return jsonify({"error": "Email or account details already exist"}), 409


@app.post("/api/hr/employees")
def create_employee():
    hr_user_id, error = require_hr_session()
    if error:
        return error

    payload = request.get_json(silent=True) or request.form
    first_name = (payload.get("firstName") or "").strip()
    last_name = (payload.get("lastName") or "").strip()
    email = (payload.get("email") or "").strip().lower()
    if not first_name or not last_name or not email:
        return jsonify({"error": "First name, last name, and email are required"}), 400

    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                log_database("FETCH", f"verify HR company user_id={hr_user_id}")
                cursor.execute("SELECT company_id, role FROM users WHERE user_id=%s AND is_active", (hr_user_id,))
                hr = cursor.fetchone()
                if not hr or hr[1] not in {"admin", "hr_officer"}:
                    return jsonify({"error": "Only Admin or HR Officer accounts can add employees"}), 403
                log_database("FETCH", "generated employee Login ID")
                cursor.execute("SELECT generate_employee_login_id(%s, %s, COALESCE(%s::date, CURRENT_DATE))", (first_name, last_name, payload.get("dateOfJoining") or None))
                login_id = cursor.fetchone()[0]
                initial_password = f"{login_id}123"
                password_hash = bcrypt.hashpw(initial_password.encode(), bcrypt.gensalt()).decode()
                log_database("INSERT", "employee account and profile")
                cursor.execute(
                    """INSERT INTO users(company_id, employee_code, login_id, email, password_hash, role, must_change_password)
                       VALUES (%s, %s, %s, %s, %s, 'employee', TRUE) RETURNING user_id""",
                    (hr[0], login_id, login_id, email, password_hash),
                )
                employee_id = cursor.fetchone()[0]
                cursor.execute(
                    """INSERT INTO employee_profiles(user_id, first_name, last_name, phone_number, department, job_title, date_of_joining)
                       VALUES (%s, %s, %s, %s, %s, %s, COALESCE(%s::date, CURRENT_DATE))""",
                    (employee_id, first_name, last_name, payload.get("phone") or None, payload.get("department") or None, payload.get("jobTitle") or None, payload.get("dateOfJoining") or None),
                )
        return jsonify({"message": "Employee created", "employeeId": employee_id, "loginId": login_id, "initialPassword": initial_password}), 201
    except psycopg.errors.UniqueViolation:
        return jsonify({"error": "An employee with this email already exists"}), 409


@app.post("/api/auth/login")
def login():
    payload = request.get_json(silent=True) or request.form
    login_id = (payload.get("loginId") or payload.get("email") or "").strip()
    password = payload.get("password") or ""

    if not login_id or not password:
        return jsonify({"error": "Login ID/email and password are required"}), 400

    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", "login user by email/Login ID")
            cursor.execute(
                """
                SELECT u.user_id, COALESCE(u.login_id, u.employee_code), u.email, u.password_hash, u.role,
                       u.must_change_password, p.first_name, p.last_name
                FROM users u
                LEFT JOIN employee_profiles p ON p.user_id = u.user_id
                WHERE u.is_active AND (u.email = %s OR u.employee_code = %s OR u.login_id = %s)
                """,
                (login_id, login_id, login_id),
            )
            user = cursor.fetchone()

            valid_password = False
            if user:
                try:
                    valid_password = bcrypt.checkpw(password.encode(), user[3].encode())
                except ValueError:
                    valid_password = False
            if not valid_password:
                return jsonify({"error": "Invalid credentials"}), 401

            cursor.execute("UPDATE users SET last_login_at = NOW() WHERE user_id = %s", (user[0],))
            log_database("UPDATE", "last login timestamp")

    session.clear()
    session["user_id"] = user[0]
    session["role"] = user[4]
    session["email"] = user[2]
    session_token = uuid4().hex
    ACTIVE_SESSIONS[session_token] = {"user_id": user[0], "role": user[4]}

    return jsonify(
        {
            "message": "Login successful",
            "user": {
                "userId": user[0],
                "employeeCode": user[1],
                "email": user[2],
                "role": user[4],
                    "name": " ".join(value for value in (user[6], user[7]) if value),
                    "mustChangePassword": user[5],
                },
            "sessionToken": session_token
        }
    )


@app.get("/api/me")
def me():
    user_id, error = require_session()
    if error:
        return error
    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", f"current session user_id={user_id}")
            cursor.execute("""SELECT u.user_id, COALESCE(u.login_id, u.employee_code) AS login_id,
                              u.email, u.role, u.must_change_password,
                              p.first_name, p.last_name, p.profile_picture_url, c.company_name, c.logo_url
                              FROM users u LEFT JOIN employee_profiles p ON p.user_id=u.user_id
                              LEFT JOIN companies c ON c.company_id=u.company_id
                              WHERE u.user_id=%s AND u.is_active""", (user_id,))
            row = cursor.fetchone()
            if not row:
                session.clear()
                return jsonify({"error": "Session user no longer exists"}), 401
            return jsonify({"userId": row[0], "loginId": row[1], "email": row[2], "role": row[3], "mustChangePassword": row[4], "name": " ".join(x for x in (row[5], row[6]) if x), "avatarUrl": row[7], "companyName": row[8], "logoUrl": row[9]})


@app.post("/api/auth/logout")
def logout():
    log_database("UPDATE", "clearing authentication session")
    token = request.headers.get("X-Session-Token")
    if token:
        ACTIVE_SESSIONS.pop(token, None)
    session.clear()
    return jsonify({"message": "Logged out"})


@app.post("/api/auth/change-password")
def change_password():
    user_id, error = require_session()
    if error:
        return error
    payload = request.get_json(silent=True) or request.form
    current_password = payload.get("currentPassword") or ""
    new_password = payload.get("newPassword") or ""
    confirmation = payload.get("confirmPassword") or ""

    if len(new_password) < 8:
        return jsonify({"error": "New password must contain at least 8 characters"}), 400
    if new_password != confirmation:
        return jsonify({"error": "New passwords do not match"}), 400

    with get_connection() as connection:
        with connection.cursor() as cursor:
            log_database("FETCH", f"password verification user_id={user_id}")
            cursor.execute("SELECT password_hash FROM users WHERE user_id=%s AND is_active", (user_id,))
            user = cursor.fetchone()
            if not user:
                return jsonify({"error": "User not found"}), 404
            try:
                valid = bcrypt.checkpw(current_password.encode(), user[0].encode())
            except ValueError:
                valid = False
            if not valid:
                return jsonify({"error": "Current password is incorrect"}), 401
            new_hash = bcrypt.hashpw(new_password.encode(), bcrypt.gensalt()).decode()
            log_database("UPDATE", f"password hash and password status user_id={user_id}")
            cursor.execute("""UPDATE users SET password_hash=%s, password_changed_at=NOW(),
                              must_change_password=FALSE, failed_login_attempts=0, locked_until=NULL
                              WHERE user_id=%s""", (new_hash, user_id))
    return jsonify({"message": "Password updated successfully"})


if __name__ == "__main__":
    app.logger.info("STARTING Flask server | database=%s", DATABASE_URL.rsplit("@", 1)[-1])
    app.run(debug=os.getenv("FLASK_DEBUG", "true").lower() == "true")
