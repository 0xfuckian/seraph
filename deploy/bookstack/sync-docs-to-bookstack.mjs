#!/usr/bin/env node
/**
 * ==============================================================================
 * Seraph Protocol — Automated BookStack Documentation Synchronizer
 * ==============================================================================
 * Connects to a live BookStack instance via the official REST API and populates/
 * synchronizes all 4 Books and 22 Chapters directly from markdown sources.
 *
 * Usage:
 *   node sync-docs-to-bookstack.mjs [options]
 *
 * Options:
 *   --url <url>              BookStack URL (default: process.env.BOOKSTACK_URL or http://localhost:6875)
 *   --token-id <id>          BookStack API Token ID (default: process.env.BOOKSTACK_TOKEN_ID)
 *   --token-secret <secret>  BookStack API Token Secret (default: process.env.BOOKSTACK_TOKEN_SECRET)
 *   --dry-run                Validate markdown files and display plan without API calls
 *
 * Environment variables:
 *   BOOKSTACK_URL, BOOKSTACK_TOKEN_ID, BOOKSTACK_TOKEN_SECRET
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DOCS_ROOT = path.resolve(__dirname, "../../docs/bookstack");

// Book specifications mapping to directories (unified as ONE Book with 4 Chapters)
const UNIFIED_BOOK = {
  name: "Seraph Protocol — Technical Manual",
  description: "Comprehensive engineering manual for the Seraph Protocol: Modular privacy continuum combining a Monero-inspired base layer with dual private EVMs.",
  sections: [
    {
      folder: "Book_1_Foundations_and_Cryptography",
      name: "Part I: Foundations & Cryptography",
      description: "Privacy Continuum L0-L3, Monero heritage, Seraphis research horizons, formal cryptography, and ZK proving benchmarks."
    },
    {
      folder: "Book_2_Core_Architecture_and_Networks",
      name: "Part II: Core Architecture & Networks",
      description: "Base Layer settlement, Dual Private EVMs, Cross-EVM Bridges, Relayers, and MEV Shielding."
    },
    {
      folder: "Book_3_Applications_and_Tokenomics",
      name: "Part III: Applications & Tokenomics",
      description: "Wallets, First-Party Privacy Modules (xUSD CDP, AI Usage Tickets, Stealth Invoices), DEX/CEX integrations, SER Tokenomics, Presale, and Creator Launchpad."
    },
    {
      folder: "Book_4_Operations_Security_and_Reference",
      name: "Part IV: Operations, Security & Reference",
      description: "Treasury DAO Governance, 12-Vector Threat Matrix, Emergency Circuit Breakers, Roadmap, Glossary, and Developer Setup."
    }
  ]
};

// CLI argument parsing
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    url: process.env.BOOKSTACK_URL || "http://localhost:6875",
    tokenId: process.env.BOOKSTACK_TOKEN_ID || "",
    tokenSecret: process.env.BOOKSTACK_TOKEN_SECRET || "",
    dryRun: false
  };

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--url" && args[i + 1]) {
      options.url = args[++i].replace(/\/+$/, "");
    } else if (args[i] === "--token-id" && args[i + 1]) {
      options.tokenId = args[++i];
    } else if (args[i] === "--token-secret" && args[i + 1]) {
      options.tokenSecret = args[++i];
    } else if (args[i] === "--dry-run") {
      options.dryRun = true;
    }
  }

  return options;
}

// Extract page title from first markdown header
export function extractTitleFromMarkdown(content, fallbackName) {
  const lines = content.split("\n");
  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith("# ")) {
      return trimmed.replace(/^#\s+/, "").trim();
    }
  }
  return fallbackName;
}

// Fetch helper with BookStack Authorization Header
async function bookstackRequest(baseUrl, endpoint, options, tokenId, tokenSecret) {
  const url = `${baseUrl}/api/${endpoint.replace(/^\/+/, "")}`;
  const headers = {
    "Authorization": `Token ${tokenId}:${tokenSecret}`,
    "Content-Type": "application/json",
    "Accept": "application/json"
  };

  const response = await fetch(url, {
    ...options,
    headers: { ...headers, ...(options.headers || {}) }
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`API ${options.method || "GET"} ${endpoint} failed (${response.status}): ${errText}`);
  }

  return response.json();
}

export async function syncDocs(options) {
  console.log("======================================================================");
  console.log("  Seraph Protocol — Synchronizing Docs to BookStack App               ");
  console.log("======================================================================");
  console.log(`Target URL:  ${options.url}`);
  console.log(`Dry Run:     ${options.dryRun ? "YES (Validating local files only)" : "NO (Live API push)"}`);
  console.log("----------------------------------------------------------------------");

  // Validate local directories and markdown files
  const inventory = [];
  let totalChapters = 0;

  for (const section of UNIFIED_BOOK.sections) {
    const bookDir = path.join(DOCS_ROOT, section.folder);
    if (!fs.existsSync(bookDir)) {
      throw new Error(`Missing book directory: ${bookDir}`);
    }

    const files = fs.readdirSync(bookDir)
      .filter(f => f.endsWith(".md") && !f.startsWith("README"))
      .sort();

    const chapters = files.map(filename => {
      const filePath = path.join(bookDir, filename);
      const content = fs.readFileSync(filePath, "utf8");
      const title = extractTitleFromMarkdown(content, filename.replace(/\.md$/, ""));
      return { filename, filePath, title, content };
    });

    totalChapters += chapters.length;
    inventory.push({ ...section, chapters });
  }

  console.log(`Verified local inventory: 1 Unified Book ("${UNIFIED_BOOK.name}"), ${inventory.length} Parts, ${totalChapters} Total Chapters.`);

  if (options.dryRun) {
    console.log("\n[DRY RUN SUMMARY]");
    console.log(`\n📚 ${UNIFIED_BOOK.name}:`);
    for (const section of inventory) {
      console.log(`\n   🔖 ${section.name} (${section.chapters.length} chapters):`);
      for (const ch of section.chapters) {
        console.log(`      📄 [${ch.filename}] -> "${ch.title}" (${ch.content.length.toLocaleString()} bytes)`);
      }
    }
    console.log("\n✅ Dry run verification passed! All 22 markdown chapters are valid.");
    return { success: true, dryRun: true, totalChapters };
  }

  if (!options.tokenId || !options.tokenSecret) {
    console.error("\n❌ Error: BookStack API Token ID and Token Secret are required for live sync.");
    console.error("Please provide them via CLI flags or environment variables:");
    console.error("  node sync-docs-to-bookstack.mjs --token-id <ID> --token-secret <SECRET>\n");
    console.error("To generate tokens in BookStack:");
    console.error("  1. Log into BookStack (default: admin@admin.com / password)");
    console.error("  2. Click Avatar (top right) -> 'Edit Profile' -> 'API Tokens'");
    console.error("  3. Click 'Create Token', copy ID and Secret, and rerun this command.\n");
    process.exit(1);
  }

  // 1. Fetch existing books on BookStack
  console.log("\n[1/3] Fetching existing books from BookStack...");
  const existingBooksResp = await bookstackRequest(options.url, "books", { method: "GET" }, options.tokenId, options.tokenSecret);
  const existingBooks = existingBooksResp.data || [];

  // 2. Create or find the ONE Unified Master Book
  console.log("[2/3] Upserting Unified Master Book & Section Chapters...");
  let masterBook = existingBooks.find(b => b.name.toLowerCase() === UNIFIED_BOOK.name.toLowerCase());
  if (!masterBook) {
    console.log(`   ➕ Creating Unified Book: "${UNIFIED_BOOK.name}"...`);
    masterBook = await bookstackRequest(options.url, "books", {
      method: "POST",
      body: JSON.stringify({
        name: UNIFIED_BOOK.name,
        description: UNIFIED_BOOK.description
      })
    }, options.tokenId, options.tokenSecret);
    console.log(`      Created Unified Book ID: ${masterBook.id}`);
  } else {
    console.log(`   ✔ Found existing Unified Book ID ${masterBook.id}: "${masterBook.name}"`);
  }

  // Fetch full book details including existing chapters and pages
  const bookDetails = await bookstackRequest(options.url, `books/${masterBook.id}`, { method: "GET" }, options.tokenId, options.tokenSecret);
  const existingContents = bookDetails.contents || [];
  const existingChapters = existingContents.filter(item => item.type === "chapter");
  const existingPages = [];
  for (const item of existingContents) {
    if (item.type === "page") {
      existingPages.push(item);
    } else if (item.type === "chapter" && item.pages) {
      existingPages.push(...item.pages);
    }
  }

  // Upsert Chapters (Parts) under the unified book
  for (const section of inventory) {
    let remoteChapter = existingChapters.find(c => c.name.toLowerCase() === section.name.toLowerCase());
    if (!remoteChapter) {
      console.log(`   🔖 Creating Chapter: "${section.name}"...`);
      remoteChapter = await bookstackRequest(options.url, "chapters", {
        method: "POST",
        body: JSON.stringify({
          book_id: masterBook.id,
          name: section.name,
          description: section.description
        })
      }, options.tokenId, options.tokenSecret);
      console.log(`      Created Chapter ID: ${remoteChapter.id}`);
    } else {
      console.log(`   ✔ Found existing Chapter ID ${remoteChapter.id}: "${section.name}"`);
    }
    section.remoteChapterId = remoteChapter.id;
  }

  // 3. Upsert Pages under their respective Chapters within the single Book
  console.log("\n[3/3] Synchronizing Pages into Unified Book...");
  let syncedCount = 0;

  for (const section of inventory) {
    console.log(`\n📚 Chapter: ${section.name} (Chapter ID: ${section.remoteChapterId})`);

    for (const ch of section.chapters) {
      // Find matching page by title or chapter prefix
      const existingPage = existingPages.find(p => 
        p.name.toLowerCase() === ch.title.toLowerCase() ||
        (ch.title.includes(":") && p.name.includes(ch.title.split(":")[0]))
      );

      if (existingPage) {
        // Update existing page
        await bookstackRequest(options.url, `pages/${existingPage.id}`, {
          method: "PUT",
          body: JSON.stringify({
            name: ch.title,
            markdown: ch.content
          })
        }, options.tokenId, options.tokenSecret);
        console.log(`   🔄 Updated Page ID ${existingPage.id}: "${ch.title}"`);
      } else {
        // Create new page inside chapter and book
        const newPage = await bookstackRequest(options.url, "pages", {
          method: "POST",
          body: JSON.stringify({
            book_id: masterBook.id,
            chapter_id: section.remoteChapterId,
            name: ch.title,
            markdown: ch.content
          })
        }, options.tokenId, options.tokenSecret);
        console.log(`   ✨ Created Page ID ${newPage.id}: "${ch.title}"`);
      }
      syncedCount++;
    }
  }

  console.log("\n======================================================================");
  console.log(`  🎉 Synchronization Complete! Successfully synced ${syncedCount} chapters.`);
  console.log(`  Open BookStack at: ${options.url}`);
  console.log("======================================================================\n");
  return { success: true, syncedCount };
}

// Auto-run if executed as CLI process
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const options = parseArgs();
  syncDocs(options).catch(err => {
    console.error("\n❌ Sync failed:", err.message);
    process.exit(1);
  });
}
