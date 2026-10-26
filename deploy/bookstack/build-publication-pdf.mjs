#!/usr/bin/env node
/**
 * Seraph Protocol — Publication-Grade Technical Manual PDF Builder
 * 
 * Fetches the unified master HTML export from BookStack, injects executive
 * cover artwork, document front matter, structured table of contents, and
 * print-optimized CSS, then compiles into a pristine, publication-grade PDF
 * using headless Google Chrome.
 */

import { writeFileSync, existsSync, mkdirSync } from "node:fs";
import { execSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = resolve(__dirname, "../..");

const BOOKSTACK_URL = process.env.BOOKSTACK_URL || "http://localhost:8000";
const TOKEN_ID = process.env.BOOKSTACK_TOKEN_ID || "XaTykmNPY2qDBqq00woyYi6ll0JMihQ6";
const TOKEN_SECRET = process.env.BOOKSTACK_TOKEN_SECRET || "fodUOWUISa0N8D1lOWRjbj3xm03ezrqR";
const BOOK_SLUG = "seraph-protocol-technical-manual";
const OUTPUT_PDF = resolve(ROOT_DIR, "docs/pdf/Seraph_Protocol_Technical_Manual.pdf");

console.log("======================================================================");
console.log("  Seraph Protocol — Publication-Grade Technical Manual PDF Builder    ");
console.log("======================================================================");

async function main() {
  console.log(`[1/4] Fetching HTML export from ${BOOKSTACK_URL}/books/${BOOK_SLUG}/export/html...`);
  
  const res = await fetch(`${BOOKSTACK_URL}/books/${BOOK_SLUG}/export/html`, {
    headers: {
      "Authorization": `Token ${TOKEN_ID}:${TOKEN_SECRET}`,
      "User-Agent": "SeraphPdfBuilder/1.0"
    }
  });

  if (!res.ok) {
    throw new Error(`Failed to fetch HTML export from BookStack: HTTP ${res.status} ${res.statusText}`);
  }

  let rawHtml = await res.text();
  console.log(`   ✔ Downloaded raw book HTML (${(rawHtml.length / 1024).toFixed(1)} KB)`);

  console.log("[2/4] Transforming content, deduplicating headings, styling callouts...");

  // 1. Remove duplicate consecutive H1 tags (BookStack page title + Markdown H1)
  rawHtml = rawHtml.replace(
    /(<h1 id="page-\d+"[^>]*>.*?<\/h1>)\s*<h1 id="bkmrk-[^"]*"[^>]*>(.*?)<\/h1>/gi,
    '$1'
  );

  // 2. Transform GitHub-style blockquotes [!NOTE], [!WARNING], [!TIP], [!IMPORTANT] into callout cards
  rawHtml = rawHtml.replace(
    /<blockquote[^>]*>\s*<p>\s*\[!(NOTE|WARNING|TIP|IMPORTANT|CAUTION)\]\s*([\s\S]*?)<\/blockquote>/gi,
    (match, alertType, content) => {
      const type = alertType.toUpperCase();
      let borderColor = "#0284c7"; // NOTE
      let badgeBg = "#e0f2fe";
      let badgeColor = "#0369a1";
      if (type === "WARNING" || type === "CAUTION") {
        borderColor = "#dc2626";
        badgeBg = "#fee2e2";
        badgeColor = "#b91c1c";
      } else if (type === "TIP") {
        borderColor = "#16a34a";
        badgeBg = "#dcfce7";
        badgeColor = "#15803d";
      } else if (type === "IMPORTANT") {
        borderColor = "#7c3aed";
        badgeBg = "#ede9fe";
        badgeColor = "#6d28d9";
      }

      return `
<div class="executive-callout" style="margin: 1.5em 0; padding: 14px 18px; border-left: 4px solid ${borderColor}; background: #f8fafc; border-radius: 0 6px 6px 0; page-break-inside: avoid;">
  <div style="display: flex; align-items: center; margin-bottom: 6px;">
    <span style="font-size: 0.72rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase; background: ${badgeBg}; color: ${badgeColor}; padding: 2px 8px; border-radius: 4px; font-family: monospace;">${type}</span>
  </div>
  <div style="font-size: 0.92rem; color: #334155; line-height: 1.55;">
    <p style="margin: 0;">${content}
  </div>
</div>`;
    }
  );

  // 3. Inject Executive Cover Page & Professional Print Stylesheet
  const executiveCoverHtml = `
<div class="executive-cover-page" style="page-break-after: always; min-height: 96vh; display: flex; flex-direction: column; justify-content: space-between; padding: 60px 40px; background: #070a11; color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; box-sizing: border-box; border-top: 6px solid #00f3ff;">
  <div>
    <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 80px;">
      <div style="display: flex; align-items: center; gap: 14px;">
        <div style="width: 38px; height: 38px; border-radius: 8px; background: linear-gradient(135deg, #00f3ff 0%, #0066ff 100%); display: flex; align-items: center; justify-content: center; font-weight: 900; font-size: 20px; color: #070a11;">S</div>
        <span style="font-size: 1.4rem; font-weight: 700; letter-spacing: 0.15em; color: #ffffff;">SERAPH PROTOCOL</span>
      </div>
      <div style="text-align: right;">
        <span style="font-size: 0.75rem; font-weight: 700; letter-spacing: 0.1em; color: #00f3ff; background: rgba(0, 243, 255, 0.1); border: 1px solid rgba(0, 243, 255, 0.3); padding: 4px 12px; border-radius: 20px; text-transform: uppercase;">v1.0.0 · Production Spec</span>
      </div>
    </div>

    <div style="margin-bottom: 40px;">
      <p style="font-size: 0.9rem; font-weight: 600; letter-spacing: 0.25em; text-transform: uppercase; color: #00f3ff; margin-bottom: 12px; font-family: monospace;">CANONICAL TECHNICAL SPECIFICATION</p>
      <h1 style="font-size: 3.2rem; font-weight: 800; line-height: 1.15; margin: 0 0 20px 0; color: #ffffff; letter-spacing: -0.02em;">
        Technical Manual:<br>
        <span style="color: #94a3b8; font-weight: 600; font-size: 2.2rem;">Architecture, Cryptography &amp; Deployment</span>
      </h1>
      <p style="font-size: 1.15rem; line-height: 1.6; color: #94a3b8; max-width: 640px; margin: 0;">
        The authoritative reference specification for Seraph Protocol — combining a Monero-inspired settlement base layer, dual private EVMs, and an on-chain privacy continuum.
      </p>
    </div>
  </div>

  <div style="border-top: 1px solid rgba(255, 255, 255, 0.12); padding-top: 32px; display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; font-size: 0.82rem;">
    <div>
      <div style="color: #64748b; font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 4px;">Primary Network</div>
      <div style="color: #ffffff; font-weight: 600; font-family: monospace;">Base Sepolia (84532)</div>
    </div>
    <div>
      <div style="color: #64748b; font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 4px;">Audited Status</div>
      <div style="color: #00f3ff; font-weight: 600;">Formal Audits Scheduled</div>
    </div>
    <div>
      <div style="color: #64748b; font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 4px;">Author / Council</div>
      <div style="color: #ffffff; font-weight: 600;">Seraph Security Council</div>
    </div>
    <div>
      <div style="color: #64748b; font-size: 0.7rem; text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 4px;">Publication Date</div>
      <div style="color: #ffffff; font-weight: 600;">October 2026</div>
    </div>
  </div>
</div>
`;

  // Inject professional print CSS
  const printCss = `
<style>
  @page {
    size: A4 portrait;
    margin: 18mm 14mm 20mm 14mm;
    @top-left {
      content: "Seraph Protocol — Technical Manual v1.0.0";
      font-size: 7.5pt;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      color: #94a3b8;
    }
    @top-right {
      content: "Base Sepolia (Chain ID 84532)";
      font-size: 7.5pt;
      font-family: monospace;
      color: #94a3b8;
    }
    @bottom-left {
      content: "CONFIDENTIAL & PROPRIETARY — FOR EVALUATION PURPOSES ONLY";
      font-size: 7.5pt;
      font-family: monospace;
      color: #94a3b8;
    }
    @bottom-right {
      content: "Page " counter(page);
      font-size: 7.5pt;
      font-family: monospace;
      font-weight: bold;
      color: #64748b;
    }
  }

  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
    font-size: 9.5pt !important;
    line-height: 1.6 !important;
    color: #1e293b !important;
    background: #ffffff !important;
  }

  h1, h2, h3, h4, h5, h6 {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif !important;
    color: #0f172a !important;
    font-weight: 700 !important;
    page-break-after: avoid !important;
  }

  h1 {
    font-size: 1.9rem !important;
    margin-top: 1.6em !important;
    margin-bottom: 0.6em !important;
    padding-bottom: 6px !important;
    border-bottom: 2px solid #e2e8f0 !important;
  }

  h2 {
    font-size: 1.35rem !important;
    margin-top: 1.4em !important;
    margin-bottom: 0.5em !important;
    padding-bottom: 4px !important;
    border-bottom: 1px solid #f1f5f9 !important;
  }

  h3 {
    font-size: 1.1rem !important;
    margin-top: 1.2em !important;
    margin-bottom: 0.4em !important;
  }

  /* Force clean page breaks on major parts and chapters */
  .chapter-hint {
    page-break-before: always !important;
    font-size: 0.8rem !important;
    font-weight: 700 !important;
    letter-spacing: 0.15em !important;
    text-transform: uppercase !important;
    color: #0284c7 !important;
    margin-top: 40px !important;
    margin-bottom: 8px !important;
    font-family: monospace !important;
  }

  .chapter-hint + h1 {
    margin-top: 0 !important;
  }

  /* Tables: Crisp executive styling */
  table {
    width: 100% !important;
    border-collapse: collapse !important;
    margin: 1.2em 0 !important;
    font-size: 8.5pt !important;
    page-break-inside: avoid !important;
    border: 1px solid #cbd5e1 !important;
  }

  th {
    background: #f1f5f9 !important;
    color: #0f172a !important;
    font-weight: 700 !important;
    text-align: left !important;
    padding: 8px 10px !important;
    border: 1px solid #cbd5e1 !important;
    font-family: monospace !important;
    font-size: 8pt !important;
    letter-spacing: 0.04em !important;
  }

  td {
    padding: 7px 10px !important;
    border: 1px solid #e2e8f0 !important;
    color: #334155 !important;
    vertical-align: top !important;
  }

  tr:nth-child(even) td {
    background: #f8fafc !important;
  }

  /* Code blocks & ASCII art diagrams */
  pre {
    background: #f8fafc !important;
    border: 1px solid #cbd5e1 !important;
    border-radius: 6px !important;
    padding: 10px 14px !important;
    font-family: "JetBrains Mono", Menlo, Monaco, Consolas, "Courier New", monospace !important;
    font-size: 8pt !important;
    line-height: 1.45 !important;
    color: #0f172a !important;
    white-space: pre-wrap !important;
    word-break: break-word !important;
    page-break-inside: avoid !important;
    margin: 1.2em 0 !important;
  }

  code {
    font-family: "JetBrains Mono", Menlo, Monaco, Consolas, monospace !important;
    font-size: 8.2pt !important;
    background: #f1f5f9 !important;
    padding: 2px 5px !important;
    border-radius: 4px !important;
    color: #0f172a !important;
  }

  pre code {
    background: transparent !important;
    padding: 0 !important;
    border: none !important;
  }

  /* Page break utilities */
  .page-break {
    page-break-after: always !important;
  }

  ul.contents {
    font-size: 9pt !important;
    line-height: 1.6 !important;
    page-break-after: always !important;
  }

  ul.contents a {
    color: #0284c7 !important;
    text-decoration: none !important;
  }

  ul.contents a:hover {
    text-decoration: underline !important;
  }
</style>
`;

  // Prepend print CSS in <head> and replace the first book title with Executive Cover
  let processedHtml = rawHtml.replace("</head>", `${printCss}</head>`);
  processedHtml = processedHtml.replace(
    /<h1 id="bkmrk-seraph-protocol-\u2014-te"[^>]*>Seraph Protocol \u2014 Technical Manual<\/h1>/i,
    executiveCoverHtml
  );
  if (!processedHtml.includes("executive-cover-page")) {
    // Fallback: replace body start
    processedHtml = processedHtml.replace(/<body[^>]*>/i, `$&${executiveCoverHtml}`);
  }

  const tempHtmlPath = "/tmp/seraph_manual_processed.html";
  writeFileSync(tempHtmlPath, processedHtml, "utf8");
  console.log(`   ✔ Injected cover page & styles, wrote to ${tempHtmlPath}`);

  console.log(`[3/4] Compiling PDF via Headless Google Chrome...`);
  if (!existsSync(dirname(OUTPUT_PDF))) {
    mkdirSync(dirname(OUTPUT_PDF), { recursive: true });
  }

  const chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
  const chromeCmd = `"${chromePath}" --headless --disable-gpu --run-all-compositor-stages-before-draw --print-to-pdf-no-header --print-to-pdf="${OUTPUT_PDF}" "${tempHtmlPath}"`;

  execSync(chromeCmd, { stdio: "inherit" });

  console.log("[4/4] Verifying generated PDF...");
  if (existsSync(OUTPUT_PDF)) {
    const stat = execSync(`ls -lh "${OUTPUT_PDF}"`).toString().trim();
    console.log(`   ✔ Successfully generated publication-grade PDF:`);
    console.log(`   ${stat}`);
  } else {
    throw new Error(`PDF generation failed: ${OUTPUT_PDF} was not created.`);
  }

  console.log("======================================================================");
  console.log("  🎉 Publication PDF Build Succeeded!                                 ");
  console.log(`  File: ${OUTPUT_PDF}`);
  console.log("======================================================================");
}

main().catch((err) => {
  console.error("❌ PDF Build Error:", err.message);
  process.exit(1);
});
