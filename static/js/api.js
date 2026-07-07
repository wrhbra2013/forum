window.API_BASE = 'https://api.projetosdinamicos.com.br/forum';
window.SITE_URL = 'https://www.projetosdinamicos.com.br';
window.APP_NAME = 'forum';

window.getToken = function() {
  var tk = localStorage.getItem(window.APP_NAME + '_token');
  var ex = localStorage.getItem(window.APP_NAME + '_session_expiry');
  if (ex && Date.now() > parseInt(ex)) {
    localStorage.removeItem(window.APP_NAME + '_token');
    localStorage.removeItem(window.APP_NAME + '_usuario');
    localStorage.removeItem(window.APP_NAME + '_session_expiry');
    return null;
  }
  return tk || null;
};

window.getUsuario = function() {
  var u = localStorage.getItem(window.APP_NAME + '_usuario');
  return u ? JSON.parse(u) : null;
};

window.rmToken = function() {
  localStorage.removeItem(window.APP_NAME + '_token');
  localStorage.removeItem(window.APP_NAME + '_usuario');
  localStorage.removeItem(window.APP_NAME + '_session_expiry');
};

window._progressTimer = null;
window._progressReq = 0;

window.progressStart = function() {
  window._progressReq++;
  var bar = document.getElementById('progressBar');
  if (!bar) return;
  bar.style.display = 'block';
  bar.style.width = '15%';
  var w = 15;
  clearInterval(window._progressTimer);
  window._progressTimer = setInterval(function() {
    if (w < 90) { w += (90 - w) * 0.08; bar.style.width = w + '%'; }
  }, 200);
};

window.progressDone = function() {
  window._progressReq = Math.max(0, window._progressReq - 1);
  if (window._progressReq > 0) return;
  var bar = document.getElementById('progressBar');
  if (!bar) return;
  clearInterval(window._progressTimer);
  bar.style.width = '100%';
  setTimeout(function() { bar.style.width = '0'; bar.style.display = 'none'; }, 400);
};

window.go = function(method, endpoint, data, cb) {
  window.progressStart();
  var token = window.getToken();
  var xhr = new XMLHttpRequest();
  xhr.open(method, window.API_BASE + endpoint, true);
  xhr.setRequestHeader('Content-Type', 'application/json');
  if (token) xhr.setRequestHeader('Authorization', 'Bearer ' + token);
  xhr.onload = function() {
    window.progressDone();
    var r;
    try { r = JSON.parse(xhr.responseText); } catch(e) { r = null; }
    if (xhr.status === 401) {
      window.rmToken();
      if (cb) cb(null, xhr.status, r);
      return;
    }
    if (cb) cb(r, xhr.status);
  };
  xhr.onerror = function() { window.progressDone(); if (cb) cb(null, 0); };
  xhr.send(data ? JSON.stringify(data) : null);
};

window.pageEnter = function(el) {
  if (!el) el = document.querySelector('.main-content');
  if (!el) return;
  el.classList.add('page-enter');
};

document.addEventListener('DOMContentLoaded', function() {
  window.pageEnter();
});

window.esc = function(s) {
  var d = document.createElement('div');
  d.textContent = s || '';
  return d.innerHTML;
};

window.fmtDate = function(d) {
  if (!d) return '';
  var dt = new Date(d);
  var agora = new Date();
  var diff = (agora - dt) / 1000;
  if (diff < 60) return 'agora';
  if (diff < 3600) return Math.floor(diff / 60) + 'min';
  if (diff < 86400) return Math.floor(diff / 3600) + 'h';
  if (diff < 2592000) return Math.floor(diff / 86400) + 'd';
  return dt.toLocaleDateString('pt-BR');
};

window.imgUrl = function(url) {
  if (!url) return window.SITE_URL + '/static/img/avatar-default.png';
  if (url.startsWith('http')) return url;
  return window.API_BASE + '/uploads/' + url;
};

window.notificar = function(msg, tipo) {
  tipo = tipo || 'info';
  var c = document.getElementById('notificacoes');
  if (!c) {
    c = document.createElement('div');
    c.id = 'notificacoes';
    c.style.cssText = 'position:fixed;top:20px;right:20px;z-index:9999;display:flex;flex-direction:column;gap:10px';
    document.body.appendChild(c);
  }
  var n = document.createElement('div');
  n.style.cssText = 'padding:14px 20px;border-radius:8px;color:#fff;font-weight:500;box-shadow:0 4px 12px rgba(0,0,0,0.2);animation:slideIn 0.3s ease;cursor:pointer;max-width:400px';
  var cores = { info: '#3498db', success: '#2ecc71', error: '#e74c3c', warning: '#f39c12' };
  n.style.background = cores[tipo] || cores.info;
  n.textContent = msg;
  n.onclick = function() { n.remove(); };
  c.appendChild(n);
  setTimeout(function() { if (n.parentNode) n.remove(); }, 5000);
};
