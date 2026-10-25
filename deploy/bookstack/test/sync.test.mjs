import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { extractTitleFromMarkdown, syncDocs } from "../sync-docs-to-bookstack.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

test("1. extractTitleFromMarkdown extracts top-level h1 correctly", () => {
  const md1 = "# Chapter 1: Monero Heritage\n\nSome text here...";
  assert.equal(extractTitleFromMarkdown(md1, "Fallback"), "Chapter 1: Monero Heritage");

  const md2 = "\n\n   #    Chapter 5: Base Layer Protocol   \n\nBody content";
  assert.equal(extractTitleFromMarkdown(md2, "Fallback"), "Chapter 5: Base Layer Protocol");

  const md3 = "No header here just plain paragraph";
  assert.equal(extractTitleFromMarkdown(md3, "FallbackTitle"), "FallbackTitle");
});

test("2. syncDocs in dry-run mode validates all 4 Books and 22 Chapters", async () => {
  const result = await syncDocs({
    url: "http://localhost:6875",
    dryRun: true
  });

  assert.equal(result.success, true);
  assert.equal(result.dryRun, true);
  assert.equal(result.totalChapters, 22);
});

test("3. BookStack deployment configuration files exist and are valid", () => {
  const composePath = path.resolve(__dirname, "../docker-compose.yml");
  const envExamplePath = path.resolve(__dirname, "../.env.example");
  const nginxPath = path.resolve(__dirname, "../nginx.conf");
  const installUbuntuPath = path.resolve(__dirname, "../install-ubuntu.sh");

  assert.ok(fs.existsSync(composePath), "docker-compose.yml must exist");
  assert.ok(fs.existsSync(envExamplePath), ".env.example must exist");
  assert.ok(fs.existsSync(nginxPath), "nginx.conf must exist");
  assert.ok(fs.existsSync(installUbuntuPath), "install-ubuntu.sh must exist");

  const composeContent = fs.readFileSync(composePath, "utf8");
  assert.ok(composeContent.includes("lscr.io/linuxserver/bookstack:latest"), "Docker Compose must use linuxserver/bookstack");
  assert.ok(composeContent.includes("mariadb:11"), "Docker Compose must use MariaDB 11");

  const envContent = fs.readFileSync(envExamplePath, "utf8");
  assert.ok(envContent.includes("APP_URL="), ".env.example must specify APP_URL");
});
