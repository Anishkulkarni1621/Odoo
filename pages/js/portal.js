(async function () {
  const page = location.pathname.split('/').pop();
  let userId;
  let role;
  let user;

  async function api(url, options = {}) {
    const headers = {...(options.headers || {})};
    const token = sessionStorage.getItem('dayflowSessionToken');
    if (token) headers['X-Session-Token'] = token;
    const response = await fetch(url, {...options, headers, credentials: 'include'});
    const data = await response.json().catch(() => ({}));
    if (response.status === 401) {
      sessionStorage.removeItem('dayflowUser');
      location.assign('/signin');
      throw new Error('Your session has expired.');
    }
    if (!response.ok) throw new Error(data.error || 'Request failed');
    return data;
  }

  function panel(title, content) {
    const element = document.createElement('section');
    document.querySelector('.live-panel')?.remove();
    element.className = 'live-panel';
    element.innerHTML = `<strong>${title}</strong><div style="margin-top:8px">${content}</div>`;
    (document.querySelector('.portal') || document.body).append(element);
    return element;
  }

  function toast(message, type = 'success') {
    document.querySelector('.toast')?.remove();
    const element = document.createElement('div');
    element.className = `toast ${type}`;
    element.textContent = message;
    document.body.append(element);
    setTimeout(() => element.remove(), 3600);
  }

  function replaceText(oldText, newText) {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    nodes.forEach(node => { if (node.nodeValue.includes(oldText)) node.nodeValue = node.nodeValue.replaceAll(oldText, newText); });
  }

  function safe(value) {
    return String(value ?? '').replace(/[&<>'"]/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[character]));
  }

  function setLiveIdentity() {
    const name = user.name || user.email;
    replaceText('Dayflow HRMS', 'Easy HR');
    replaceText('Sarah Jenkins', name);
    replaceText('Alex', name.split(' ')[0]);
  }

  function mountAccountBar() {
    const bar = document.createElement('div');
    bar.className = 'account-bar';
    const logo = user.logoUrl ? `<img src="${user.logoUrl}" alt="Company logo">` : '<img src="/assets/branding/easy-hr-service.jpeg" alt="Easy HR logo">';
    bar.innerHTML = `${logo}<span class="account-company">${user.companyName || 'HRMS'}</span><span class="account-user">${user.name || user.email}</span><button type="button" data-logout>Log out</button>`;
    document.body.prepend(bar);
  }

  function mountSidebar() {
    if (document.querySelector('.app-sidebar')) return;
    const employeeLinks = [
      ['Overview', 'emp_dashboard.html'], ['My leave', 'leave_application.html'],
      ['Attendance', 'attendance.html'], ['My profile', 'employee_profile.html'],
      ['Salary', 'salary.html'], ['Notifications', 'notifications.html']
    ];
    const hrLinks = [
      ['Overview', 'HR_dashboard.html'], ['Directory', 'HR_emp_page.html'],
      ['Attendance', 'hr_emps_attendance.html'], ['Leave approvals', 'HR_leaves_app.html'],
      ['Payroll', 'salary_management.html'], ['Settings', 'company_settings.html'],
      ['Notifications', 'notifications.html']
    ];
    const links = role === 'employee' ? employeeLinks : hrLinks;
    const base = role === 'employee' ? '/pages/employee/' : '/pages/hr/';
    const initials = (user.name || user.email || 'U').split(/\s+/).map(x => x[0]).slice(0, 2).join('').toUpperCase();
    // Keep the service mark and the company's logo independent. A company logo
    // must never be reused as a user's profile/avatar image.
    const avatar = user.avatarUrl || '/assets/branding/easy-hr-service.jpeg';
    const avatarMarkup = avatar ? `<img src="${avatar}" alt="Profile picture">` : `<span class="sidebar-initials">${initials}</span>`;
    const sidebar = document.createElement('aside');
    sidebar.className = 'app-sidebar';
    sidebar.innerHTML = `<div class="brand-mark"><img class="brand-logo" src="/assets/branding/easy-hr-service.jpeg" alt="Easy HR logo"><span>Easy HR <small>people workspace</small></span></div>
      <div class="sidebar-profile">${avatarMarkup}<strong>${user.name || user.email}</strong><small>${role === 'employee' ? 'Employee workspace' : 'HR workspace'}</small></div>
      <div class="sidebar-heading">Workspace</div><nav class="sidebar-nav">${links.slice(0, 4).map(([label, file]) => `<a href="${base}${file}" class="${file === page ? 'active' : ''}"><span class="nav-dot"></span>${label}</a>`).join('')}</nav>
      <div class="sidebar-heading sidebar-heading-manage">Manage</div><nav class="sidebar-nav">${links.slice(4).map(([label, file]) => `<a href="${base}${file}" class="${file === page ? 'active' : ''}"><span class="nav-dot"></span>${label}</a>`).join('')}</nav>
      <button class="sidebar-logout" type="button" data-logout>Log out</button>`;
    document.body.prepend(sidebar);
    const toggle = document.createElement('button');
    toggle.className = 'sidebar-toggle'; toggle.type = 'button'; toggle.textContent = '☰'; toggle.setAttribute('aria-label', 'Open navigation');
    toggle.addEventListener('click', () => sidebar.classList.toggle('open'));
    document.body.prepend(toggle);
  }

  async function loadEmployeeDashboard() {
    const data = await api('/api/dashboard/employee');
    const balances = data.leaveBalances.length ? data.leaveBalances.map(x => `${x.leave_type}: ${x.remaining_days} remaining`).join(' · ') : 'No leave balances configured';
    panel('Live employee data', `${user.name || user.email} · ${balances} · ${data.attendance.length} attendance records loaded`);
    wireButton('Check In', () => api('/api/attendance/check-in', {method: 'POST'}).then(() => location.reload()));
    wireButton('Check Out', () => api('/api/attendance/check-out', {method: 'POST'}).then(() => location.reload()));
  }

  async function loadHrDashboard() {
    const data = await api('/api/dashboard/hr');
    panel('Live HR data', `${data.employees.employee_count} employees · ${data.pendingLeaves.pending_leave_count} pending leave requests`);
    wireButton('Add Employee', () => location.assign('/pages/hr/add_employee.html'));
  }

  async function enhanceEmployeeDashboard() {
    const data = await api('/api/dashboard/employee');
    const balances = data.leaveBalances.length ? data.leaveBalances.map(x => `${x.leave_type}: ${x.remaining_days}`).join(' · ') : 'No balances configured';
    panel('Live employee overview', `<div class="live-stats"><span><b>${data.attendance.length}</b><small>Recent attendance records</small></span><span><b>${data.leaveSummary.pending || 0}</b><small>Pending leave requests</small></span><span><b>${safe(balances)}</b><small>Current leave balance</small></span></div>`);
  }

  async function enhanceHrDashboard() {
    const data = await api('/api/dashboard/hr');
    const present = data.attendance.reduce((total, item) => total + Number(item.count || 0), 0);
    panel('Live organization overview', `<div class="live-stats"><span><b>${data.employees.employee_count}</b><small>Active employees</small></span><span><b>${data.pendingLeaves.pending_leave_count}</b><small>Pending approvals</small></span><span><b>${present}</b><small>Attendance records today</small></span></div>`);
  }

  async function loadDirectory() {
    const list = document.getElementById('employeeList');
    const search = document.getElementById('employeeSearch');
    if (!list) return;
    const render = async () => {
      list.innerHTML = '<p class="loading-state">Loading employee directory…</p>';
      const data = await api(`/api/employees?search=${encodeURIComponent(search?.value || '')}`);
      list.innerHTML = data.employees.length ? data.employees.map(employee => `<a class="employee-card" href="/pages/hr/HR_emp_page.html?user_id=${employee.user_id}"><span class="employee-avatar">${safe((employee.first_name || 'U')[0])}${safe((employee.last_name || '')[0] || '')}</span><span><strong>${safe(`${employee.first_name || ''} ${employee.last_name || ''}`.trim())}</strong><small>${safe(employee.job_title || employee.department || 'Employee')} · ${safe(employee.email)}</small></span><span class="employee-status">${safe(employee.employment_status || 'Active')}</span></a>`).join('') : '<p class="empty-state">No employees match this search.</p>';
    };
    search?.addEventListener('input', () => { clearTimeout(search._timer); search._timer = setTimeout(render, 250); });
    await render();
  }

  async function loadProfile() {
    const requestedId = new URLSearchParams(location.search).get('user_id') || userId;
    const {employee} = await api(`/api/employees/${requestedId}`);
    const name = `${employee.first_name || ''} ${employee.last_name || ''}`.trim();
    panel('Live employee profile', `${name} · ${employee.email || ''} · ${employee.department || 'Department not set'} · Login ID: ${employee.login_id || 'Not set'}`);
    replaceText('Sarah Jenkins', name || user.email);
  }

  async function loadAttendance() {
    const data = await api('/api/attendance');
    panel('Live attendance data', `${data.attendance.length} records loaded from PostgreSQL`);
    wireButton('Check In', () => api('/api/attendance/check-in', {method: 'POST'}).then(() => location.reload()));
  }

  async function enhanceAttendance() {
    const target = document.getElementById('attendanceData');
    if (!target) return;
    const data = await api('/api/attendance');
    target.innerHTML = data.attendance.length ? `<div class="table-wrap"><table class="data-table"><thead><tr><th>Employee</th><th>Date</th><th>Check in</th><th>Check out</th><th>Work minutes</th><th>Status</th></tr></thead><tbody>${data.attendance.map(row => `<tr><td>${safe(row.employee_name || user.name)}</td><td>${safe(row.attendance_date)}</td><td>${safe(row.check_in_time || '—')}</td><td>${safe(row.check_out_time || '—')}</td><td>${safe(row.work_minutes || 0)}</td><td><span class="status-badge">${safe(row.status || 'present')}</span></td></tr>`).join('')}</tbody></table></div>` : '<p class="empty-state">No attendance records found.</p>';
  }

  async function loadLeavePage() {
    const [balances, requests] = await Promise.all([api('/api/leave-balances'), api('/api/leaves')]);
    const balanceText = balances.balances.length ? balances.balances.map(x => `${x.leave_type}: ${x.remaining_days}`).join(' · ') : 'No balances configured';
    panel('Live leave data', `${balanceText} · ${requests.leaves.length} requests loaded`);
    const form = document.querySelector('form');
    const submit = form && [...form.querySelectorAll('button')].find(button => /submit|apply/i.test(button.textContent));
    if (!submit) return;
    submit.addEventListener('click', async event => {
      event.preventDefault();
      const start = document.getElementById('start_date')?.value || form.querySelector('[name="start_date"]')?.value;
      const end = document.getElementById('end_date')?.value || form.querySelector('[name="end_date"]')?.value;
      if (!start || !end) return panel('Leave request', '<span style="color:#b91c1c">Select start and end dates.</span>');
      await api('/api/leaves', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({leave_type: form.querySelector('input[name="leave_type"]:checked')?.value || form.querySelector('[name="leave_type"]')?.value || 'paid', start_date: start, end_date: end, remarks: document.getElementById('reason')?.value || form.querySelector('[name="remarks"]')?.value || ''})});
      location.reload();
    });
  }

  async function loadHrLeaves() {
    const data = await api('/api/dashboard/hr');
    const live = panel('Live leave approvals', `${data.leaveRequests.length} pending requests loaded`);
    data.leaveRequests.forEach(item => {
      const row = document.createElement('div');
      row.style.cssText = 'display:flex;gap:8px;align-items:center;margin-top:8px;';
      row.innerHTML = `<span style="flex:1">Leave #${item.leave_id} · ${item.leave_type} · ${item.start_date} to ${item.end_date}</span><button data-status="approved">Approve</button><button data-status="rejected">Reject</button>`;
      row.querySelectorAll('button').forEach(button => button.addEventListener('click', async () => {
        await api(`/api/leaves/${item.leave_id}`, {method: 'PATCH', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({status: button.dataset.status})});
        location.reload();
      }));
      live.append(row);
    });
  }

  function loadAddEmployee() {
    const form = document.getElementById('addEmployeeForm');
    const message = document.getElementById('employeeMessage');
    if (!form) return;
    form.addEventListener('submit', async event => {
      event.preventDefault();
      const button = form.querySelector('button[type="submit"]');
      button.disabled = true;
      message.textContent = 'Creating employee account...';
      try {
        const data = await api('/api/hr/employees', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(Object.fromEntries(new FormData(form)))});
        message.style.color = '#15803d';
        message.innerHTML = `Employee created. Login ID: <strong>${data.loginId}</strong><br>Initial password: <strong>${data.initialPassword}</strong>`;
        form.reset();
      } catch (error) { message.style.color = '#b91c1c'; message.textContent = error.message; }
      finally { button.disabled = false; }
    });
  }

  function loadPasswordPage() {
    const form = document.getElementById('passwordForm');
    const message = document.getElementById('passwordMessage');
    if (!form) return;
    document.querySelectorAll('[data-toggle-password]').forEach(toggle => toggle.addEventListener('click', () => {
      const input = document.getElementById(toggle.dataset.togglePassword);
      if (!input) return;
      input.type = input.type === 'password' ? 'text' : 'password';
      toggle.textContent = input.type === 'password' ? 'Show' : 'Hide';
    }));
    const strength = document.getElementById('passwordStrength');
    const newPassword = document.getElementById('newPassword');
    newPassword?.addEventListener('input', () => {
      const value = newPassword.value;
      const score = Number(value.length >= 8) + Number(/[A-Z]/.test(value) && /[a-z]/.test(value)) + Number(/\d/.test(value) && /[^A-Za-z0-9]/.test(value));
      strength?.classList.remove('weak', 'medium', 'strong');
      if (score <= 1) strength?.classList.add('weak'); else if (score === 2) strength?.classList.add('medium'); else strength?.classList.add('strong');
    });
    form.addEventListener('submit', async event => {
      event.preventDefault();
      const button = form.querySelector('button[type="submit"]');
      button.disabled = true;
      try {
        if (form.newPassword.value !== form.confirmPassword.value) throw new Error('New passwords do not match.');
        const data = await api('/api/auth/change-password', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(Object.fromEntries(new FormData(form)))});
        message.style.color = '#15803d'; message.textContent = data.message; form.reset();
        user.mustChangePassword = false; sessionStorage.setItem('dayflowUser', JSON.stringify(user));
        setTimeout(() => location.assign('/pages/employee/emp_dashboard.html'), 700);
      } catch (error) { message.style.color = '#b91c1c'; message.textContent = error.message; }
      finally { button.disabled = false; }
    });
  }

  function wireButton(label, action) {
    const button = [...document.querySelectorAll('button')].find(item => item.textContent.trim().toLowerCase() === label.toLowerCase());
    if (button && !button.dataset.wired) {
      button.dataset.wired = 'true';
      button.addEventListener('click', async () => {
        button.disabled = true;
        try { await action(); toast(`${label} completed.`); }
        catch (error) { toast(error.message, 'error'); }
        finally { button.disabled = false; }
      });
    }
  }

  async function logout() {
    await api('/api/auth/logout', {method: 'POST'});
    sessionStorage.removeItem('dayflowUser');
    sessionStorage.removeItem('dayflowSessionToken');
    location.assign('/signin');
  }

  try {
    const cachedUser = JSON.parse(sessionStorage.getItem('dayflowUser') || 'null');
    if (cachedUser) { user = cachedUser; role = cachedUser.role || 'employee'; mountSidebar(); }
    user = await api('/api/me');
    userId = user.userId; role = user.role;
    sessionStorage.setItem('dayflowUser', JSON.stringify(user));
    mountSidebar();
    setLiveIdentity();
    const hrPages = new Set(['HR_dashboard.html', 'HR_emp_page.html', 'hr_emps_attendance.html', 'HR_leaves_app.html', 'add_employee.html', 'salary_management.html', 'leave_allocation.html', 'company_settings.html', 'attendance_corrections.html', 'notifications.html']);
    const employeePages = new Set(['emp_dashboard.html', 'employee_profile.html', 'private_information.html', 'resume.html', 'salary.html', 'leave_application.html', 'attendance.html', 'notifications.html', 'update_password.html']);
    if (role === 'employee' && hrPages.has(page)) return location.replace('/pages/employee/emp_dashboard.html');
    if (['admin', 'hr_officer'].includes(role) && employeePages.has(page)) return location.replace('/pages/hr/HR_dashboard.html');

    const loaders = {'emp_dashboard.html': async () => { await loadEmployeeDashboard(); await enhanceEmployeeDashboard(); }, 'HR_dashboard.html': async () => { await loadHrDashboard(); await enhanceHrDashboard(); }, 'HR_emp_page.html': (role === 'employee' || location.search) ? loadProfile : loadDirectory, 'employee_profile.html': loadProfile, 'hr_emps_attendance.html': async () => { await loadAttendance(); await enhanceAttendance(); }, 'attendance.html': async () => { await loadAttendance(); await enhanceAttendance(); }, 'leave_application.html': loadLeavePage, 'add_employee.html': loadAddEmployee, 'update_password.html': loadPasswordPage, 'HR_leaves_app.html': loadHrLeaves};
    const navigation = {'Directory': role === 'employee' ? '/pages/employee/emp_dashboard.html' : '/pages/hr/HR_dashboard.html', 'Attendance': role === 'employee' ? '/pages/employee/emp_dashboard.html' : '/pages/hr/hr_emps_attendance.html', 'Leave': role === 'employee' ? '/pages/employee/leave_application.html' : '/pages/hr/HR_leaves_app.html', 'Profile': role === 'employee' ? '/pages/employee/employee_profile.html' : `/pages/hr/HR_emp_page.html?user_id=${userId}`};
    document.querySelectorAll('a').forEach(link => { const label = link.textContent.trim(); if (navigation[label]) link.href = navigation[label]; });
    document.querySelectorAll('a, button').forEach(link => { if (link.matches('[data-logout]') || /log\s*out/i.test(link.textContent)) { if (link.tagName === 'A') link.href = '#'; link.addEventListener('click', event => { event.preventDefault(); logout(); }); } });
    await (loaders[page] || function () {})();
  } catch (error) {
    if (error.message !== 'Your session has expired.') panel('Session', `<span style="color:#b91c1c">${error.message}</span>`);
  }
})();
