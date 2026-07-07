document.currentScript.insertAdjacentHTML('afterend', `
<div class="progress-bar" id="progressBar"></div>
<header class="forum-header">
  <div class="header-top">
    <div class="container header-flex">
      <div class="header-brand">
        <a href="${window.SITE_URL || '/'}" class="header-logo">
          <span class="logo-3d">
            <svg viewBox="0 0 512 512" width="36" height="36" xmlns="http://www.w3.org/2000/svg">
              <defs>
                <linearGradient id="hdr1" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stop-color="#6c5ce7"/><stop offset="100%" stop-color="#a29bfe"/>
                </linearGradient>
                <linearGradient id="hdr2" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stop-color="#00b894"/><stop offset="100%" stop-color="#00a381"/>
                </linearGradient>
                <linearGradient id="hdr3" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stop-color="#fd79a8"/><stop offset="100%" stop-color="#e84393"/>
                </linearGradient>
                <filter id="hdShad">
                  <feDropShadow dx="0" dy="4" stdDeviation="6" flood-color="#2d3436" flood-opacity="0.2"/>
                </filter>
              </defs>
              <circle cx="256" cy="256" r="240" fill="url(#hdr1)" filter="url(#hdShad)"/>
              <path d="M140,200 Q140,155 185,155 L270,155 Q315,155 315,200 L315,260 Q315,305 270,305 L245,305 L220,335 L225,305 L185,305 Q140,305 140,260 Z" fill="url(#hdr2)" stroke="rgba(255,255,255,0.15)" stroke-width="1.5"/>
              <rect x="165" y="185" width="120" height="8" rx="4" fill="rgba(255,255,255,0.5)"/>
              <rect x="165" y="205" width="90" height="8" rx="4" fill="rgba(255,255,255,0.35)"/>
              <rect x="165" y="225" width="105" height="8" rx="4" fill="rgba(255,255,255,0.35)"/>
              <rect x="230" y="200" width="95" height="7" rx="3.5" fill="rgba(255,255,255,0.5)"/>
              <path d="M230,200 Q230,165 265,165 L335,165 Q370,165 370,200 L370,250 Q370,285 335,285 L315,285 L295,310 L300,285 L265,285 Q230,285 230,250 Z" fill="url(#hdr3)" stroke="rgba(255,255,255,0.15)" stroke-width="1.5"/>
              <rect x="250" y="190" width="75" height="7" rx="3.5" fill="rgba(255,255,255,0.5)"/>
              <rect x="250" y="207" width="55" height="7" rx="3.5" fill="rgba(255,255,255,0.35)"/>
            </svg>
            <span class="logo-text">FORUMM</span>
          </span>
        </a>
      </div>
      <div class="header-search" id="headerSearch">
        <i class="fas fa-search search-icon"></i>
        <input type="text" id="searchInput" placeholder="Pesquisar perguntas..." autocomplete="off">
        <div class="search-results" id="searchResults"></div>
      </div>
      <nav class="header-nav" id="headerNav">
        <a href="/" class="nav-link"><i class="fas fa-home"></i> Início</a>
        <a href="/perguntas.html" class="nav-link"><i class="fas fa-question-circle"></i> Perguntas</a>
        <a href="/categorias.html" class="nav-link"><i class="fas fa-th-large"></i> Categorias</a>
      </nav>
      <div class="header-actions" id="headerActions">
        <div class="user-menu" id="userMenu" style="display:none">
          <button class="btn-user" onclick="toggleUserDropdown()">
            <img id="userAvatar" src="" alt="" class="avatar-sm">
            <span id="userName"></span>
            <i class="fas fa-chevron-down"></i>
          </button>
          <div class="user-dropdown" id="userDropdown">
            <a href="/perfil.html"><i class="fas fa-user"></i> Meu Perfil</a>
            <a href="/minhas-perguntas.html"><i class="fas fa-question"></i> Minhas Perguntas</a>
            <a href="#" onclick="sair()"><i class="fas fa-sign-out-alt"></i> Sair</a>
          </div>
        </div>
        <div class="auth-buttons" id="authButtons">
          <a href="/login.html" class="btn btn-outline">Entrar</a>
          <a href="/cadastro.html" class="btn btn-primary">Cadastrar</a>
        </div>
        <a href="/nova-pergunta.html" class="btn btn-accent" id="btnNovaPergunta">
          <i class="fas fa-plus"></i> Perguntar
        </a>
      </div>
    </div>
  </div>
</header>

<style>
@keyframes slideIn { from { opacity:0; transform:translateX(100px); } to { opacity:1; transform:translateX(0); } }
@keyframes spin { to { transform:rotate(360deg); } }
</style>

<script>
(function() {
  var u = window.getUsuario();
  var token = window.getToken();
  var userMenu = document.getElementById('userMenu');
  var authButtons = document.getElementById('authButtons');

  if (token && u) {
    userMenu.style.display = 'flex';
    authButtons.style.display = 'none';
    document.getElementById('userName').textContent = u.nome || u.usuario;
    document.getElementById('userAvatar').src = u.avatar ? window.imgUrl(u.avatar) : window.SITE_URL + '/static/img/avatar-default.png';
  }

  // Search
  var searchInput = document.getElementById('searchInput');
  var searchResults = document.getElementById('searchResults');
  var searchTimer;

  searchInput.addEventListener('input', function() {
    clearTimeout(searchTimer);
    var q = this.value.trim();
    if (q.length < 2) { searchResults.style.display = 'none'; return; }
    searchTimer = setTimeout(function() {
      window.go('GET', '/search?q=' + encodeURIComponent(q), null, function(r) {
        if (r && r.results && r.results.length > 0) {
          searchResults.innerHTML = r.results.map(function(item) {
            return '<a href="/pergunta.html?id=' + item.id + '" class="search-item">' +
              '<div class="search-item-title">' + window.esc(item.titulo) + '</div>' +
              '<div class="search-item-meta">' + window.esc(item.categoria || '') + '</div>' +
              '</a>';
          }).join('');
          searchResults.style.display = 'block';
        } else {
          searchResults.innerHTML = '<div class="search-empty">Nenhum resultado</div>';
          searchResults.style.display = 'block';
        }
      });
    }, 300);
  });

  document.addEventListener('click', function(e) {
    if (!searchInput.contains(e.target) && !searchResults.contains(e.target)) {
      searchResults.style.display = 'none';
    }
  });
})();

window.toggleUserDropdown = function() {
  var dd = document.getElementById('userDropdown');
  dd.style.display = dd.style.display === 'block' ? 'none' : 'block';
};

window.sair = function() {
  window.rmToken();
  window.location.href = '/';
};

document.addEventListener('click', function(e) {
  var dd = document.getElementById('userDropdown');
  if (dd && !e.target.closest('.user-menu')) dd.style.display = 'none';
});
</script>
`);
