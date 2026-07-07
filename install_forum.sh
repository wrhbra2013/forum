#!/bin/sh
set -eu

# ==============================================================
# Script de instalação — API FORUMM (Docker)
# Uso: sudo bash install_forum.sh [install|uninstall|logs|reset]
# ==============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2; }
error() { printf "${RED}[ERRO]${NC} %s\n" "$1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Execute como root: sudo bash install_forum.sh"

# === CONFIGURAÇÃO ===
APP_NAME="forum"
DB_NAME="${APP_NAME}_db"
APP_PORT=3005
DATA_DIR="/var/www/${APP_NAME}"
ADMIN_EMAIL="admin@forumrespostas.com.br"
ADMIN_NOME="admin"
ADMIN_PASS="@admin123"
SITE_URL="https://www.projetosdinamicos.com.br"
API_URL="https://api.projetosdinamicos.com.br"

install_flow() {
  info "==== Instalação da API FORUMM ===="

  mkdir -p "$DATA_DIR/api/src" "$DATA_DIR/db/init" "$DATA_DIR"/{pgdata,uploads,backups}

  # === docker-compose.yml ===
  info "Gerando docker-compose.yml..."
  cat > "$DATA_DIR/docker-compose.yml" << EOF
services:
  db:
    image: postgres:16-alpine
    container_name: ${APP_NAME}-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: ${DB_NAME}
      ADMIN_EMAIL: ${ADMIN_EMAIL}
      ADMIN_NOME: ${ADMIN_NOME}
      ADMIN_PASS: ${ADMIN_PASS}
    volumes:
      - ${DATA_DIR}/pgdata:/var/lib/postgresql/data
      - ./db/init/01-schema.sql:/docker-entrypoint-initdb.d/01-schema.sql:ro
      - ./db/init/02-seed.sh:/docker-entrypoint-initdb.d/02-seed.sh:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d ${DB_NAME}"]
      interval: 10s
      timeout: 5s
      retries: 5

  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    container_name: ${APP_NAME}-api
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      APP_NAME: ${APP_NAME}
      DB_HOST: db
      DB_PORT: 5432
      DB_NAME: ${DB_NAME}
      DB_USER: postgres
      DB_PASS: postgres
      API_TOKEN: \${API_TOKEN}
      SITE_URL: ${SITE_URL}
      API_URL: ${API_URL}
    volumes:
      - ${DATA_DIR}/uploads:/app/uploads
      - ${DATA_DIR}/backups:/app/backups
      - ./api/src:/app/src
    ports:
      - "${APP_PORT}:3000"
EOF

  # === api/Dockerfile ===
  info "Gerando api/Dockerfile..."
  cat > "$DATA_DIR/api/Dockerfile" << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY src/ ./src/
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
RUN mkdir -p /app/uploads /app/backups && chown -R appuser:appgroup /app
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1
CMD ["node", "src/server.js"]
EOF

  # === api/package.json ===
  info "Gerando api/package.json..."
  cat > "$DATA_DIR/api/package.json" << EOF
{
  "name": "${APP_NAME}-api",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node src/server.js",
    "dev": "node --watch src/server.js"
  },
  "dependencies": {
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.21.0",
    "pg": "^8.12.0"
  }
}
EOF

  # === api/src/server.js ===
  info "Gerando server.js..."
  cat > "$DATA_DIR/api/src/server.js" << 'SERVEREOF'
const { Pool } = require('pg');
const express = require('express');
const path = require('path');
const crypto = require('crypto');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3000;
const PROJETO = process.env.APP_NAME || 'forum';
const API_TOKEN = process.env.API_TOKEN || '';
const SITE_URL = process.env.SITE_URL || 'https://www.projetosdinamicos.com.br';

const pool = new Pool({
    host: process.env.DB_HOST || 'db',
    port: process.env.DB_PORT || 5432,
    database: process.env.DB_NAME || 'forum_db',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASS || 'postgres'
});

pool.on('error', (err) => console.error('DB Error:', err));

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

const corsOptions = {
    origin: [
        SITE_URL,
        'https://www.projetosdinamicos.com.br',
        'https://projetosdinamicos.com.br',
        'https://api.projetosdinamicos.com.br'
    ],
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
    credentials: true
};
app.use(cors(corsOptions));

app.use((req, res, next) => {
    if (req.method === 'GET' || req.method === 'HEAD' || req.path === '/' || req.path === '/health' || req.path.startsWith('/auth/')) return next();
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
});

app.use('/uploads', express.static(path.join(__dirname, '..', 'uploads')));

async function tabelaExiste(tabela) {
    const result = await pool.query(
        `SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = $1)`,
        [tabela]
    );
    return result.rows[0].exists;
}

async function garantirColunas(tabela, data) {
    const chaves = Object.keys(data);
    if (chaves.length === 0) return;
    try {
        const result = await pool.query(
            `SELECT column_name FROM information_schema.columns WHERE table_name = $1`,
            [tabela]
        );
        const colunasExistentes = new Set(result.rows.map(r => r.column_name));
        const novas = chaves.filter(k => !colunasExistentes.has(k));
        for (const coluna of novas) {
            await pool.query(`ALTER TABLE "${tabela}" ADD COLUMN "${coluna}" TEXT`);
            console.log(`Coluna "${coluna}" criada em "${tabela}"`);
        }
    } catch (err) {
        console.error('Erro ao garantir colunas:', err.message);
    }
}

async function garantirTabela(tabela, data) {
    if (await tabelaExiste(tabela)) return;
    const cols = Object.keys(data)
        .filter(k => k !== 'id')
        .map(k => `"${k}" TEXT`)
        .join(', ');
    await pool.query(`
        CREATE TABLE IF NOT EXISTS "${tabela}" (
            id SERIAL PRIMARY KEY,
            ${cols},
            created_at TIMESTAMP DEFAULT NOW()
        )
    `);
    console.log(`Tabela "${tabela}" criada dinamicamente`);
}

// === Health ===
app.get('/', (req, res) => {
    res.json({
        message: 'API Forum Respostas',
        status: 'OK',
        project: PROJETO,
        timestamp: new Date().toISOString()
    });
});

app.get('/health', async (req, res) => {
    const base = { status: 'healthy', project: PROJETO, timestamp: new Date().toISOString() };
    try {
        await pool.query('SELECT 1');
        res.json({ ...base, database: 'connected' });
    } catch (err) {
        res.json({ ...base, status: 'unhealthy', database: 'disconnected', error: err.message });
    }
});

// === Auth ===
app.post('/auth/login', async (req, res) => {
    const { email, senha } = req.body;
    if (!email || !senha) {
        return res.status(400).json({ error: 'Email e senha são obrigatórios' });
    }
    try {
        const result = await pool.query(
            'SELECT id, nome, email, admin, avatar, bio, reputacao FROM login WHERE email = $1 AND senha = $2',
            [email, senha]
        );
        if (result.rows.length === 0) {
            return res.status(401).json({ error: 'Email ou senha inválidos' });
        }
        const user = result.rows[0];
        res.json({
            success: true,
            token: API_TOKEN,
            usuario: user,
            session_expiry: Date.now() + 86400000
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/auth/cadastro', async (req, res) => {
    const { nome, email, senha } = req.body;
    if (!nome || !email || !senha) {
        return res.status(400).json({ error: 'Nome, email e senha são obrigatórios' });
    }
    try {
        const existente = await pool.query('SELECT id FROM login WHERE email = $1', [email]);
        if (existente.rows.length > 0) {
            return res.status(409).json({ error: 'Email já cadastrado' });
        }
        const result = await pool.query(
            'INSERT INTO login (nome, email, senha) VALUES ($1, $2, $3) RETURNING id, nome, email, admin, avatar, bio, reputacao',
            [nome, email, senha]
        );
        const user = result.rows[0];
        res.json({
            success: true,
            token: API_TOKEN,
            usuario: user,
            session_expiry: Date.now() + 86400000
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/auth/usuario', async (req, res) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const { id } = req.query;
    if (!id) return res.status(400).json({ error: 'ID obrigatório' });
    try {
        const result = await pool.query(
            'SELECT id, nome, email, admin, avatar, bio, reputacao, created_at FROM login WHERE id = $1',
            [id]
        );
        if (result.rows.length === 0) return res.status(404).json({ error: 'Usuário não encontrado' });
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/auth/usuario', async (req, res) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const { id, nome, avatar, bio } = req.body;
    if (!id) return res.status(400).json({ error: 'ID obrigatório' });
    try {
        const result = await pool.query(
            'UPDATE login SET nome = COALESCE($1, nome), avatar = COALESCE($2, avatar), bio = COALESCE($3, bio) WHERE id = $4 RETURNING id, nome, email, admin, avatar, bio, reputacao',
            [nome, avatar, bio, id]
        );
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// === Categorias ===
app.get('/categorias', async (req, res) => {
    try {
        if (!(await tabelaExiste('categorias'))) return res.json([]);
        const result = await pool.query(`
            SELECT c.*,
                (SELECT COUNT(*) FROM perguntas WHERE categoria_id = c.id) as total_perguntas,
                (SELECT COUNT(*) FROM perguntas WHERE categoria_id = c.id AND status = 'aberta') as perguntas_abertas
            FROM categorias c ORDER BY c.nome ASC
        `);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// === Perguntas ===
app.get('/perguntas', async (req, res) => {
    try {
        if (!(await tabelaExiste('perguntas'))) return res.json({ perguntas: [], total: 0 });
        const { categoria_id, status, busca, pagina, limite } = req.query;
        const page = Math.max(1, parseInt(pagina) || 1);
        const limit = Math.min(50, Math.max(1, parseInt(limite) || 20));
        const offset = (page - 1) * limit;

        let where = ['1=1'];
        let params = [];
        let idx = 1;

        if (categoria_id) {
            where.push(`p.categoria_id = $${idx++}`);
            params.push(categoria_id);
        }
        if (status) {
            where.push(`p.status = $${idx++}`);
            params.push(status);
        }
        if (busca) {
            where.push(`(LOWER(p.titulo) LIKE $${idx} OR LOWER(p.descricao) LIKE $${idx})`);
            params.push(`%${busca.toLowerCase()}%`);
            idx++;
        }

        const countResult = await pool.query(
            `SELECT COUNT(*) FROM perguntas p WHERE ${where.join(' AND ')}`,
            params
        );
        const total = parseInt(countResult.rows[0].count);

        const result = await pool.query(
            `SELECT p.*, l.nome as autor_nome, l.avatar as autor_avatar,
                (SELECT COUNT(*) FROM respostas WHERE pergunta_id = p.id) as total_respostas,
                (SELECT COUNT(*) FROM respostas WHERE pergunta_id = p.id AND melhor_resposta = true) as tem_melhor_resposta
             FROM perguntas p
             LEFT JOIN login l ON l.id = p.usuario_id
             WHERE ${where.join(' AND ')}
             ORDER BY p.created_at DESC
             LIMIT $${idx++} OFFSET $${idx++}`,
            [...params, limit, offset]
        );

        res.json({ perguntas: result.rows, total, pagina: page, total_paginas: Math.ceil(total / limit) });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/perguntas/:id', async (req, res) => {
    const { id } = req.params;
    try {
        const result = await pool.query(
            `SELECT p.*, l.nome as autor_nome, l.avatar as autor_avatar, l.bio as autor_bio, l.reputacao as autor_reputacao,
                c.nome as categoria_nome, c.slug as categoria_slug, c.icone as categoria_icone
             FROM perguntas p
             LEFT JOIN login l ON l.id = p.usuario_id
             LEFT JOIN categorias c ON c.id = p.categoria_id
             WHERE p.id = $1`,
            [id]
        );
        if (result.rows.length === 0) return res.status(404).json({ error: 'Pergunta não encontrada' });

        // Incrementar visualizacoes
        await pool.query('UPDATE perguntas SET visualizacoes = COALESCE(visualizacoes,0) + 1 WHERE id = $1', [id]);

        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/perguntas', async (req, res) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const { titulo, descricao, categoria_id, tags } = req.body;
    const usuario_id = req.body.usuario_id;
    if (!titulo || !descricao || !categoria_id || !usuario_id) {
        return res.status(400).json({ error: 'Título, descrição, categoria e usuário são obrigatórios' });
    }
    try {
        // Criar tabela dinamicamente se não existir
        await garantirTabela('perguntas', { titulo: '', descricao: '', categoria_id: '', usuario_id: '', status: '', tags: '', visualizacoes: '' });
        await garantirColunas('perguntas', { titulo, descricao, categoria_id, usuario_id, tags });

        const result = await pool.query(
            `INSERT INTO perguntas (titulo, descricao, categoria_id, usuario_id, status, tags, visualizacoes)
             VALUES ($1, $2, $3, $4, 'aberta', $5, 0) RETURNING *`,
            [titulo, descricao, categoria_id, usuario_id, tags || '']
        );
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/perguntas/:id', async (req, res) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    const { titulo, descricao, categoria_id, status, tags } = req.body;
    try {
        await garantirColunas('perguntas', req.body);
        const result = await pool.query(
            `UPDATE perguntas SET titulo = COALESCE($1, titulo), descricao = COALESCE($2, descricao),
             categoria_id = COALESCE($3, categoria_id), status = COALESCE($4, status),
             tags = COALESCE($5, tags), atualizado_em = NOW()
             WHERE id = $6 RETURNING *`,
            [titulo, descricao, categoria_id, status, tags, id]
        );
        res.json(result.rows[0] || { error: 'Pergunta não encontrada' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/perguntas/:id', async (req, res) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    try {
        await pool.query('DELETE FROM respostas WHERE pergunta_id = $1', [id]);
        await pool.query('DELETE FROM perguntas WHERE id = $1', [id]);
        res.json({ success: true, message: 'Pergunta excluída' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// === Respostas ===
app.get('/respostas/pergunta/:pergunta_id', async (req, res) => {
    const { pergunta_id } = req.params;
    try {
        if (!(await tabelaExiste('respostas'))) return res.json([]);
        const result = await pool.query(
            `SELECT r.*, l.nome as autor_nome, l.avatar as autor_avatar, l.reputacao as autor_reputacao
             FROM respostas r
             LEFT JOIN login l ON l.id = r.usuario_id
             WHERE r.pergunta_id = $1
             ORDER BY r.melhor_resposta DESC, r.votos DESC, r.created_at ASC`,
            [pergunta_id]
        );
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/respostas', async (req, res) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const { pergunta_id, usuario_id, conteudo } = req.body;
    if (!pergunta_id || !usuario_id || !conteudo) {
        return res.status(400).json({ error: 'Pergunta, usuário e conteúdo são obrigatórios' });
    }
    try {
        await garantirTabela('respostas', { pergunta_id: '', usuario_id: '', conteudo: '', melhor_resposta: '', votos: '' });
        await garantirColunas('respostas', { pergunta_id, usuario_id, conteudo });

        const result = await pool.query(
            `INSERT INTO respostas (pergunta_id, usuario_id, conteudo, melhor_resposta, votos)
             VALUES ($1, $2, $3, false, 0) RETURNING *`,
            [pergunta_id, usuario_id, conteudo]
        );
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Marcar melhor resposta (só o autor da pergunta pode)
app.put('/respostas/:id/melhor-resposta', async (req, res) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    const { usuario_id } = req.body;
    try {
        // Verificar se a resposta existe e pegar a pergunta
        const resposta = await pool.query('SELECT * FROM respostas WHERE id = $1', [id]);
        if (resposta.rows.length === 0) return res.status(404).json({ error: 'Resposta não encontrada' });

        const pergunta = await pool.query('SELECT * FROM perguntas WHERE id = $1', [resposta.rows[0].pergunta_id]);
        if (pergunta.rows.length === 0) return res.status(404).json({ error: 'Pergunta não encontrada' });

        // Verificar se o usuário é o autor da pergunta
        if (pergunta.rows[0].usuario_id != usuario_id) {
            return res.status(403).json({ error: 'Apenas o autor da pergunta pode escolher a melhor resposta' });
        }

        // Remover melhor resposta anterior
        await pool.query(
            'UPDATE respostas SET melhor_resposta = false WHERE pergunta_id = $1',
            [resposta.rows[0].pergunta_id]
        );

        // Marcar nova melhor resposta
        const result = await pool.query(
            'UPDATE respostas SET melhor_resposta = true WHERE id = $1 RETURNING *',
            [id]
        );

        // Atualizar status da pergunta para resolvida
        await pool.query(
            "UPDATE perguntas SET status = 'resolvida', atualizado_em = NOW() WHERE id = $1",
            [resposta.rows[0].pergunta_id]
        );

        // Aumentar reputação do autor da resposta
        await pool.query(
            'UPDATE login SET reputacao = COALESCE(reputacao,0) + 10 WHERE id = $1',
            [resposta.rows[0].usuario_id]
        );

        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Votar em resposta
app.post('/respostas/:id/votar', async (req, res) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const { id } = req.params;
    const { usuario_id, tipo } = req.body;
    if (!usuario_id || !tipo || !['up', 'down'].includes(tipo)) {
        return res.status(400).json({ error: 'Usuário e tipo (up/down) são obrigatórios' });
    }
    try {
        await garantirTabela('votos', { usuario_id: '', resposta_id: '', tipo: '' });
        await garantirColunas('votos', { usuario_id, resposta_id: id, tipo });

        // Verificar se já votou
        const existente = await pool.query(
            'SELECT id, tipo FROM votos WHERE usuario_id = $1 AND resposta_id = $2',
            [usuario_id, id]
        );

        if (existente.rows.length > 0) {
            if (existente.rows[0].tipo === tipo) {
                // Remover voto (toggle)
                await pool.query('DELETE FROM votos WHERE id = $1', [existente.rows[0].id]);
                const delta = tipo === 'up' ? -1 : 1;
                await pool.query('UPDATE respostas SET votos = COALESCE(votos,0) + $1 WHERE id = $2', [delta, id]);
            } else {
                // Mudar voto
                await pool.query('UPDATE votos SET tipo = $1 WHERE id = $2', [tipo, existente.rows[0].id]);
                const delta = tipo === 'up' ? 2 : -2;
                await pool.query('UPDATE respostas SET votos = COALESCE(votos,0) + $1 WHERE id = $2', [delta, id]);
            }
        } else {
            await pool.query(
                'INSERT INTO votos (usuario_id, resposta_id, tipo) VALUES ($1, $2, $3)',
                [usuario_id, id, tipo]
            );
            const delta = tipo === 'up' ? 1 : -1;
            await pool.query('UPDATE respostas SET votos = COALESCE(votos,0) + $1 WHERE id = $2', [delta, id]);
        }

        const resposta = await pool.query('SELECT id, votos FROM respostas WHERE id = $1', [id]);
        res.json(resposta.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Voto status
app.get('/votos/resposta/:resposta_id', async (req, res) => {
    const { resposta_id } = req.params;
    try {
        if (!(await tabelaExiste('votos'))) return res.json([]);
        const result = await pool.query('SELECT usuario_id, tipo FROM votos WHERE resposta_id = $1', [resposta_id]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// === Comentários ===
app.get('/comentarios/resposta/:resposta_id', async (req, res) => {
    const { resposta_id } = req.params;
    try {
        if (!(await tabelaExiste('comentarios'))) return res.json([]);
        const result = await pool.query(
            `SELECT c.*, l.nome as autor_nome, l.avatar as autor_avatar
             FROM comentarios c
             LEFT JOIN login l ON l.id = c.usuario_id
             WHERE c.resposta_id = $1 ORDER BY c.created_at ASC`,
            [resposta_id]
        );
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/comentarios', async (req, res) => {
    const auth = req.headers.authorization;
    if (!auth || !auth.startsWith('Bearer ') || auth.slice(7) !== API_TOKEN) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    const { resposta_id, usuario_id, conteudo } = req.body;
    if (!resposta_id || !usuario_id || !conteudo) {
        return res.status(400).json({ error: 'Resposta, usuário e conteúdo são obrigatórios' });
    }
    try {
        await garantirTabela('comentarios', { resposta_id: '', usuario_id: '', conteudo: '' });
        await garantirColunas('comentarios', { resposta_id, usuario_id, conteudo });
        const result = await pool.query(
            'INSERT INTO comentarios (resposta_id, usuario_id, conteudo) VALUES ($1, $2, $3) RETURNING *',
            [resposta_id, usuario_id, conteudo]
        );
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// === Dashboard ===
app.get('/dashboard', async (req, res) => {
    try {
        const stats = {};

        // Total de perguntas
        if (await tabelaExiste('perguntas')) {
            const r = await pool.query('SELECT COUNT(*) as count FROM perguntas');
            stats.total_perguntas = parseInt(r.rows[0].count);

            const r2 = await pool.query('SELECT status, COUNT(*) as count FROM perguntas GROUP BY status');
            stats.perguntas_por_status = r2.rows;
        } else {
            stats.total_perguntas = 0;
            stats.perguntas_por_status = [];
        }

        // Total de respostas
        if (await tabelaExiste('respostas')) {
            const r = await pool.query('SELECT COUNT(*) as count FROM respostas');
            stats.total_respostas = parseInt(r.rows[0].count);

            const r2 = await pool.query('SELECT COUNT(*) as count FROM respostas WHERE melhor_resposta = true');
            stats.melhores_respostas = parseInt(r2.rows[0].count);
        } else {
            stats.total_respostas = 0;
            stats.melhores_respostas = 0;
        }

        // Total de usuarios
        if (await tabelaExiste('login')) {
            const r = await pool.query('SELECT COUNT(*) as count FROM login');
            stats.total_usuarios = parseInt(r.rows[0].count);
        } else {
            stats.total_usuarios = 0;
        }

        // Total de categorias
        if (await tabelaExiste('categorias')) {
            const r = await pool.query('SELECT COUNT(*) as count FROM categorias');
            stats.total_categorias = parseInt(r.rows[0].count);
        } else {
            stats.total_categorias = 0;
        }

        // Perguntas por categoria
        if (await tabelaExiste('perguntas') && await tabelaExiste('categorias')) {
            const r = await pool.query(
                `SELECT c.id, c.nome, c.slug, c.icone, COUNT(p.id) as total
                 FROM categorias c LEFT JOIN perguntas p ON p.categoria_id = c.id
                 GROUP BY c.id, c.nome, c.slug, c.icone ORDER BY total DESC`
            );
            stats.perguntas_por_categoria = r.rows;
        } else {
            stats.perguntas_por_categoria = [];
        }

        // Destaques: perguntas com melhor resposta (uma por categoria)
        if (await tabelaExiste('perguntas') && await tabelaExiste('respostas') && await tabelaExiste('categorias')) {
            const r = await pool.query(
                `SELECT DISTINCT ON (p.categoria_id)
                    p.id, p.titulo, p.descricao, p.categoria_id, p.created_at,
                    c.nome as categoria_nome, c.slug as categoria_slug, c.icone as categoria_icone,
                    l.nome as autor_nome, l.avatar as autor_avatar,
                    r.id as resposta_id, r.conteudo as resposta_conteudo,
                    r.created_at as resposta_data,
                    la.nome as resposta_autor_nome, la.avatar as resposta_autor_avatar
                 FROM perguntas p
                 INNER JOIN respostas r ON r.pergunta_id = p.id AND r.melhor_resposta = true
                 LEFT JOIN categorias c ON c.id = p.categoria_id
                 LEFT JOIN login l ON l.id = p.usuario_id
                 LEFT JOIN login la ON la.id = r.usuario_id
                 WHERE p.status = 'resolvida'
                 ORDER BY p.categoria_id, r.votos DESC`
            );
            stats.destaques = r.rows;
        } else {
            stats.destaques = [];
        }

        // Usuarios com mais reputacao
        if (await tabelaExiste('login')) {
            const r = await pool.query(
                'SELECT id, nome, avatar, reputacao FROM login ORDER BY reputacao DESC LIMIT 10'
            );
            stats.top_usuarios = r.rows;
        } else {
            stats.top_usuarios = [];
        }

        res.json(stats);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// === Search ===
app.get('/search', async (req, res) => {
    const { q } = req.query;
    if (!q || q.length < 2) return res.json({ results: [] });
    try {
        const term = '%' + q.toLowerCase() + '%';
        const results = [];

        if (await tabelaExiste('perguntas')) {
            const r = await pool.query(
                `SELECT p.id, p.titulo, LEFT(p.descricao, 150) as descricao, 'pergunta' as tipo,
                    c.nome as categoria
                 FROM perguntas p
                 LEFT JOIN categorias c ON c.id = p.categoria_id
                 WHERE LOWER(p.titulo) LIKE $1 OR LOWER(p.descricao) LIKE $1
                 LIMIT 10`,
                [term]
            );
            results.push(...r.rows);
        }

        res.json({ results });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// === CRUD Dinâmico (admin) ===
app.get('/:tabela', async (req, res) => {
    const { tabela } = req.params;
    if (!(await tabelaExiste(tabela))) {
        return res.status(404).json({ error: 'Tabela não encontrada' });
    }
    try {
        const result = await pool.query(`SELECT * FROM "${tabela}" ORDER BY id DESC LIMIT 500`);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/:tabela', async (req, res) => {
    const { tabela } = req.params;
    const data = req.body;
    try {
        await garantirTabela(tabela, data);
        await garantirColunas(tabela, data);
        const keys = Object.keys(data).map(k => `"${k}"`).join(', ');
        const values = Object.keys(data).map((_, i) => `$${i + 1}`).join(', ');
        const result = await pool.query(
            `INSERT INTO "${tabela}" (${keys}) VALUES (${values}) RETURNING *;`,
            Object.values(data)
        );
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/:tabela/:id', async (req, res) => {
    const { tabela, id } = req.params;
    if (!(await tabelaExiste(tabela))) {
        return res.status(404).json({ error: 'Tabela não encontrada' });
    }
    const data = req.body;
    try {
        await garantirColunas(tabela, data);
        const keys = Object.keys(data).map((k, i) => `"${k}" = $${i + 1}`).join(', ');
        const result = await pool.query(
            `UPDATE "${tabela}" SET ${keys} WHERE id = $${Object.keys(data).length + 1} RETURNING *;`,
            [...Object.values(data), id]
        );
        res.json(result.rows[0] || { error: 'Registro não encontrado' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/:tabela/:id', async (req, res) => {
    const { tabela, id } = req.params;
    if (!(await tabelaExiste(tabela))) {
        return res.status(404).json({ error: 'Tabela não encontrada' });
    }
    try {
        await pool.query(`DELETE FROM "${tabela}" WHERE id = $1`, [id]);
        res.json({ success: true, message: 'Registro excluído' });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.listen(PORT, () => {
    console.log(`Forum API running on port ${PORT}`);
});
SERVEREOF

  # === db/init/01-schema.sql ===
  info "Gerando schema do banco..."
  cat > "$DATA_DIR/db/init/01-schema.sql" << 'EOSQL'
CREATE TABLE IF NOT EXISTS settings (
    chave VARCHAR(100) PRIMARY KEY,
    valor TEXT
);

CREATE TABLE IF NOT EXISTS login (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    senha VARCHAR(255) NOT NULL,
    admin BOOLEAN DEFAULT false,
    avatar TEXT,
    bio TEXT,
    reputacao INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS categorias (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(100) NOT NULL,
    descricao TEXT,
    icone VARCHAR(50) DEFAULT 'question-circle',
    slug VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS perguntas (
    id SERIAL PRIMARY KEY,
    titulo VARCHAR(300) NOT NULL,
    descricao TEXT NOT NULL,
    categoria_id INTEGER REFERENCES categorias(id),
    usuario_id INTEGER REFERENCES login(id),
    status VARCHAR(20) DEFAULT 'aberta',
    tags TEXT,
    visualizacoes INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    atualizado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS respostas (
    id SERIAL PRIMARY KEY,
    pergunta_id INTEGER REFERENCES perguntas(id) ON DELETE CASCADE,
    usuario_id INTEGER REFERENCES login(id),
    conteudo TEXT NOT NULL,
    melhor_resposta BOOLEAN DEFAULT false,
    votos INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS comentarios (
    id SERIAL PRIMARY KEY,
    resposta_id INTEGER REFERENCES respostas(id) ON DELETE CASCADE,
    usuario_id INTEGER REFERENCES login(id),
    conteudo TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS votos (
    id SERIAL PRIMARY KEY,
    usuario_id INTEGER REFERENCES login(id),
    resposta_id INTEGER REFERENCES respostas(id) ON DELETE CASCADE,
    tipo VARCHAR(10) NOT NULL,
    UNIQUE(usuario_id, resposta_id)
);
EOSQL

  # === db/init/02-seed.sh ===
  info "Gerando seed..."
  cat > "$DATA_DIR/db/init/02-seed.sh" << EOF
#!/bin/bash
set -e
psql -v ON_ERROR_STOP=1 --username "\$POSTGRES_USER" --dbname "\$POSTGRES_DB" <<-EOSQL
    INSERT INTO login (nome, email, senha, admin, reputacao)
    VALUES ('${ADMIN_NOME}', '${ADMIN_EMAIL}', '${ADMIN_PASS}', true, 100)
    ON CONFLICT (email) DO NOTHING;

    INSERT INTO categorias (nome, descricao, icone, slug) VALUES
    ('Tecnologia', 'Perguntas sobre programação, hardware, software e TI', 'laptop-code', 'tecnologia'),
    ('Ciência', 'Discussões sobre ciência, pesquisa e descobertas', 'flask', 'ciencia'),
    ('Saúde', 'Dúvidas sobre saúde, bem-estar e medicina', 'heart-pulse', 'saude'),
    ('Educação', 'Perguntas sobre estudos, cursos e aprendizado', 'graduation-cap', 'educacao'),
    ('Negócios', 'Discussões sobre empreendedorismo, finanças e carreira', 'briefcase', 'negocios'),
    ('Entretenimento', 'Filmes, séries, música, jogos e cultura', 'film', 'entretenimento'),
    ('Casa e Jardim', 'Dicas sobre decoração, jardinagem e reformas', 'home', 'casa-jardim'),
    ('Esportes', 'Perguntas sobre esportes e atividades físicas', 'running', 'esportes'),
    ('Gastronomia', 'Receitas, restaurantes e culinária', 'utensils', 'gastronomia'),
    ('Viagem', 'Dicas de viagem, destinos e turismo', 'plane', 'viagem')
    ON CONFLICT (slug) DO NOTHING;

    INSERT INTO settings (chave, valor) VALUES
    ('site_nome', 'FORUMM'),
    ('site_descricao', 'Comunidade colaborativa FORUMM'),
    ('admin_email', '${ADMIN_EMAIL}')
    ON CONFLICT (chave) DO NOTHING;
EOSQL
EOF
  chmod +x "$DATA_DIR/db/init/02-seed.sh"

  # === API_TOKEN ===
  API_TOKEN=$(openssl rand -hex 32)

  # === .env ===
  info "Criando .env..."
  cat > "$DATA_DIR/.env" << EOF
PORT=${APP_PORT}
APP_NAME=${APP_NAME}
DATA_DIR=${DATA_DIR}
DB_HOST=db
DB_PORT=5432
DB_NAME=${DB_NAME}
DB_USER=postgres
DB_PASS=postgres
API_TOKEN=${API_TOKEN}
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_NOME=${ADMIN_NOME}
ADMIN_PASS=${ADMIN_PASS}
SITE_URL=${SITE_URL}
API_URL=${API_URL}
EOF

  cat > "$SCRIPT_DIR/.env" << EOF
APP_NAME=${APP_NAME}
DATA_DIR=${DATA_DIR}
EOF

  # === static/js/api_token.js ===
  mkdir -p "$DATA_DIR/static/js"
  cat > "$DATA_DIR/static/js/api_token.js" << EOF
window.API_TOKEN = '${API_TOKEN}';
EOF

  # === Build containers ===
  info "Construindo containers..."
  docker compose -f "$DATA_DIR/docker-compose.yml" down 2>/dev/null || true
  docker compose -f "$DATA_DIR/docker-compose.yml" up -d --build || {
    error "Falha ao construir containers"
    exit 1
  }

  # === Nginx ===
  NGINX_LOCATIONS="/etc/nginx/${APP_NAME}-locations.conf"
  cat > "$NGINX_LOCATIONS" << EOF
location /${APP_NAME}/ {
    rewrite ^/${APP_NAME}/(.*) /\$1 break;
    proxy_pass http://127.0.0.1:${APP_PORT}/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
}
EOF

  NGINX_CONF="/etc/nginx/sites-available/default"
  if [ -f "$NGINX_CONF" ] && ! grep -q "${APP_NAME}-locations.conf" "$NGINX_CONF"; then
    sed -i "/server_name api\.projetosdinamicos\.com\.br;/a\    include ${NGINX_LOCATIONS};" "$NGINX_CONF" 2>/dev/null || true
  fi
  nginx -t 2>/dev/null && systemctl reload nginx.service 2>/dev/null || true

  echo ""
  info "===== Instalação concluída! ====="
  echo ""
  echo "  Projeto:   ${APP_NAME}"
  echo "  API:       http://localhost:${APP_PORT}"
  echo "  Health:    http://localhost:${APP_PORT}/health"
  echo "  Publica:   ${API_URL}/${APP_NAME}/"
  echo "  Dashboard: ${API_URL}/${APP_NAME}/dashboard"
  echo "  Admin:     ${ADMIN_EMAIL} / ${ADMIN_PASS}"
  echo ""
  echo "  Token:    ${API_TOKEN}"
  echo ""
  echo "  Próximo passo: atualize static/js/api.js com as informações:"
  echo "  window.API_BASE = '${API_URL}/${APP_NAME}';"
  echo "  window.SITE_URL = '${SITE_URL}';"
  echo ""
}

case "${1:-install}" in
  install|"") install_flow ;;
  uninstall)
    echo "Desinstalação..."
    docker compose -f "${DATA_DIR}/docker-compose.yml" down 2>/dev/null || true
    rm -rf "${DATA_DIR}"
    rm -f "/etc/nginx/${APP_NAME}-locations.conf"
    nginx -t 2>/dev/null && systemctl reload nginx.service 2>/dev/null || true
    echo "Removido."
    ;;
  logs)
    docker logs "${APP_NAME}-api" --tail 30 2>&1 || echo "Container não encontrado"
    ;;
  reset)
    docker compose -f "${DATA_DIR}/docker-compose.yml" down -v 2>/dev/null || true
    rm -rf "${DATA_DIR}/pgdata"
    install_flow
    ;;
  *) error "Uso: $0 {install|uninstall|logs|reset}" ;;
esac
