const login = document.getElementById('login');
const confirmForm = document.getElementById('confirm');
const status = document.getElementById('status');
const credsWrap = document.getElementById('creds-wrap');
const totpWrap = document.getElementById('totp-wrap');
const confirmPwWrap = document.getElementById('confirm-password-wrap');
const confirmTotpWrap = document.getElementById('confirm-totp-wrap');
const reauthHint = document.getElementById('reauth-oauth-hint');

const params = new URLSearchParams(location.search);
let pendingOauthCode = params.get('oauth') === '2fa' ? (params.get('code') || '') : '';

async function api(path, method = 'GET', body) {
  const r = await fetch('/api' + path, {
    method,
    credentials: 'same-origin',
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  const d = await r.json().catch(() => ({}));
  if (!r.ok) {
    const err = Error(d.error || 'Không thực hiện được.');
    err.requires2fa = !!d.requires2fa;
    throw err;
  }
  return d;
}

async function ready() {
  const info = await api('/me/account-deletion');
  document.getElementById('identity').textContent = 'Bạn đang yêu cầu xóa tài khoản @' + info.username + '.';
  const hasOauth = Array.isArray(info.oauthProviders) && info.oauthProviders.length > 0;
  if (confirmPwWrap) confirmPwWrap.hidden = !info.requiresPassword;
  if (confirmTotpWrap) confirmTotpWrap.hidden = !(info.requiresPassword && info.twoFactorEnabled);
  if (reauthHint) reauthHint.hidden = !(info.requiresPassword && hasOauth);
  login.hidden = true;
  confirmForm.hidden = false;
}

if (pendingOauthCode) {
  credsWrap.hidden = true;
  for (const inp of credsWrap.querySelectorAll('input')) inp.required = false;
  totpWrap.hidden = false;
  totpWrap.querySelector('input').required = true;
  status.textContent = 'Nhập mã xác thực 2 lớp (2FA) để hoàn tất đăng nhập.';
} else {
  if (params.get('oauth_error') === 'not_found') {
    status.textContent = 'Tài khoản liên kết này chưa gắn với tài khoản Kinnect nào.';
  } else if (params.get('oauth_error')) {
    status.textContent = 'Không hoàn tất được đăng nhập liên kết. Vui lòng thử lại.';
  }
  ready().catch(() => {});
}

login.addEventListener('submit', async e => {
  e.preventDefault();
  const b = login.querySelector('button');
  b.disabled = true;
  status.textContent = 'Đang xác thực…';
  try {
    const data = new FormData(login);
    const totpCode = String(data.get('totpCode') || '').trim();
    if (pendingOauthCode) {
      await api('/oauth/app-session', 'POST', { code: pendingOauthCode, totpCode });
      pendingOauthCode = '';
      history.replaceState(null, '', '/delete-account');
    } else {
      await api('/login', 'POST', {
        username: data.get('username'),
        password: data.get('password'),
        ...(totpCode ? { totpCode } : {}),
        remember: false,
      });
    }
    login.reset();
    await ready();
    status.textContent = 'Chưa có dữ liệu nào bị xóa. Đọc kỹ và xác nhận bên dưới.';
  } catch (error) {
    if (error.requires2fa) {
      totpWrap.hidden = false;
      const otpInput = totpWrap.querySelector('input');
      otpInput.required = true;
      otpInput.focus();
    }
    status.textContent = error.message;
  } finally {
    b.disabled = false;
  }
});

confirmForm.addEventListener('submit', async e => {
  e.preventDefault();
  if (!confirmForm.reportValidity()) return;
  const b = confirmForm.querySelector('button');
  b.disabled = true;
  status.textContent = 'Đang xử lý…';
  try {
    const data = new FormData(confirmForm);
    const pw = String(data.get('password') || '');
    const totpCode = String(data.get('totpCode') || '').trim();
    await api('/me/account-deletion', 'DELETE', {
      confirmUsername: data.get('confirmUsername'),
      ...(pw ? { password: pw } : {}),
      ...(totpCode ? { totpCode } : {}),
      confirmDelete: data.get('confirmed') === 'on',
    });
    confirmForm.reset();
    confirmForm.hidden = true;
    status.textContent = 'Đã xóa vĩnh viễn tài khoản và dữ liệu khỏi hệ thống đang hoạt động. Mọi phiên đăng nhập đã bị thu hồi.';
  } catch (error) {
    status.textContent = error.message;
  } finally {
    b.disabled = false;
  }
});
