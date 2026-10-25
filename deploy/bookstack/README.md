# Seraph Protocol — Live BookStack Deployment & Sync Suite

This directory contains the deployment stack and automated synchronization engine to host the official **Seraph Protocol Documentation** on a live instance of [BookStackApp](https://www.bookstackapp.com/docs/admin/installation/).

---

## Architecture Overview

```
+-------------------------------------------------------------------------+
|                  Seraph Markdown Sources (docs/bookstack/)               |
|   Book 1 (Ch 00-04) | Book 2 (Ch 05-09) | Book 3 (Ch 10-15) | Book 4   |
+------------------------------------+------------------------------------+
                                     │
                                     ▼  sync-docs-to-bookstack.mjs
+-------------------------------------------------------------------------+
|                    BookStack REST API (HTTP Bearer Token)               |
|      POST /api/books               │      POST /api/pages (markdown)    |
+------------------------------------+------------------------------------+
                                     │
                                     ▼
+-------------------------------------------------------------------------+
|                     Live BookStack Application Instance                 |
|   - Docker Container (linuxserver/bookstack) / Native Ubuntu 22.04+     |
|   - MariaDB 11 Persistent Storage Engine                                |
|   - Nginx Reverse Proxy (SSL) -> docs.seraphprotocol.tech               |
+-------------------------------------------------------------------------+
```

---

## Method 1: Instant Docker Compose (Recommended)

The fastest and most reliable way to spin up a fully configured BookStack instance.

### 1. Prerequisites
Ensure [Docker](https://docs.docker.com/get-docker/) and Docker Compose are installed on your machine or VPS.

### 2. Configure Environment
```bash
cd deploy/bookstack
cp .env.example .env
```

Edit `.env` to set your desired domain/IP and database passwords:
```env
APP_URL=http://localhost:6875   # Or https://docs.seraphprotocol.tech
APP_PORT=6875
DB_PASSWORD=your_secure_password
DB_ROOT_PASSWORD=your_secure_root_password
```

### 3. Launch BookStack
```bash
docker compose up -d
```

BookStack is now running at `http://localhost:6875` (or your configured port/IP).

* **Default Admin Email:** `admin@admin.com`
* **Default Password:** `password`

*(Important: Change the default admin password immediately upon first login!)*

---

## Method 2: Official Ubuntu LTS Script (Bare Metal / VPS)

If you are running an Ubuntu 22.04 or 24.04 LTS server and prefer native PHP/MySQL/Nginx installation without Docker, use the automated installer based on [official BookStack devops scripts](https://www.bookstackapp.com/docs/admin/installation/):

```bash
# Run with sudo on your Ubuntu server:
sudo ./install-ubuntu.sh docs.seraphprotocol.tech
```

The script will:
1. Detect your Ubuntu version.
2. Download the verified devops installation script from `BookStackApp/devops`.
3. Install PHP 8.2+, MariaDB, and Nginx.
4. Configure BookStack at `/var/www/bookstack`.

---

## Method 3: Nginx Reverse Proxy & SSL Setup

To serve BookStack under `https://docs.seraphprotocol.tech` with automatic Let's Encrypt SSL:

1. Copy the provided Nginx configuration to your system:
   ```bash
   sudo cp deploy/bookstack/nginx.conf /etc/nginx/sites-available/bookstack.conf
   sudo ln -s /etc/nginx/sites-available/bookstack.conf /etc/nginx/sites-enabled/
   ```

2. Issue a free SSL certificate via Certbot:
   ```bash
   sudo certbot --nginx -d docs.seraphprotocol.tech
   sudo systemctl reload nginx
   ```

---

## Automated Documentation Sync (Push All 22 Chapters)

Once your BookStack instance is running, use our automated sync script to create all **4 Books** and import all **22 Chapters** into the live wiki in one command:

### 1. Generate BookStack API Token
1. Log into your BookStack instance as Administrator.
2. In the top-right header, click your user avatar and select **Edit Profile**.
3. Scroll down to the **API Tokens** section and click **Create Token**.
4. Name the token (e.g. `seraph-docs-sync`) and click Save.
5. Copy both the **Token ID** and **Token Secret** (the secret is only displayed once).

### 2. Run the Synchronization Script

#### Dry-Run Mode (Test Local Markdown Files)
```bash
node sync-docs-to-bookstack.mjs --dry-run
```

#### Live Sync to BookStack
```bash
node sync-docs-to-bookstack.mjs \
  --url "http://localhost:6875" \
  --token-id "<YOUR_TOKEN_ID>" \
  --token-secret "<YOUR_TOKEN_SECRET>"
```

Or via environment variables:
```bash
export BOOKSTACK_URL="http://localhost:6875"
export BOOKSTACK_TOKEN_ID="<YOUR_TOKEN_ID>"
export BOOKSTACK_TOKEN_SECRET="<YOUR_TOKEN_SECRET>"

npm run sync --prefix deploy/bookstack
```

### What the Sync Script Does
1. **Idempotent Book Creation**: Queries `GET /api/books` and creates the 4 Books if they do not exist:
   * *Book 1: Foundations & Cryptography*
   * *Book 2: Core Architecture & Networks*
   * *Book 3: Applications & Tokenomics*
   * *Book 4: Operations, Security & Reference*
2. **Title & Markdown Extraction**: Reads every `.md` chapter file in order, extracting the `# Chapter X:` header.
3. **Upsert Pages**: Queries `GET /api/books/{id}`. If the chapter page exists, it updates it via `PUT /api/pages/{id}`; if new, it creates it via `POST /api/pages` preserving native Markdown formatting, mathematical formulas, and ASCII diagrams.
4. **Re-Runnable**: You can run this script whenever documentation is updated in the git repo to keep your live BookStack wiki 100% up to date.

---

## Running the Automated Test Suite

Verify that all deployment configurations, sync logic, and markdown chapter files are valid:

```bash
npm test --prefix deploy/bookstack
```
