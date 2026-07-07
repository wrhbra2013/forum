document.currentScript.insertAdjacentHTML('afterend', `
<div class="progress-bar" id="progressBar"></div>
<header class="forum-header">
  <div class="header-top">
    <div class="container header-flex">
      <div class="header-brand">
        <a href="${window.SITE_URL || '/'}" class="header-logo">
          <i class="fas fa-comments"></i>
          <span>Fórum Respostas</span>
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
