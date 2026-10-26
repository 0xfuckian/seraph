import fs from 'node:fs';
import path from 'node:path';

const indexPath = path.resolve('website/index.html');
let html = fs.readFileSync(indexPath, 'utf8');

// 1. Replace Google Fonts with IoskeleyMonoTerm @font-face
const googleFontTag = /<link href="https:\/\/fonts\.googleapis\.com\/css2\?family=Space\+Grotesk[^"]*" rel="stylesheet">/i;
const fontFaceDeclaration = `<!-- Typography: IoskeleyMonoTerm (Universal Monospace Terminal Font) -->
  <style>
    @font-face {
      font-family: 'IoskeleyMonoTerm';
      src: url('fonts/IoskeleyMonoTerm-Regular.ttf') format('truetype'),
           url('/fonts/IoskeleyMonoTerm-Regular.ttf') format('truetype');
      font-weight: 100 900;
      font-style: normal;
      font-display: swap;
    }
    *, *::before, *::after {
      font-family: 'IoskeleyMonoTerm', monospace !important;
    }
    html, body, button, input, select, textarea, h1, h2, h3, h4, h5, h6, p, a, span, table, th, td, div, code, pre, label {
      font-family: 'IoskeleyMonoTerm', monospace !important;
    }
  </style>`;

if (googleFontTag.test(html)) {
  html = html.replace(googleFontTag, fontFaceDeclaration);
} else {
  html = html.replace('</head>', `${fontFaceDeclaration}\n</head>`);
}

// 2. Replace all occurrences of Space Grotesk and JetBrains Mono with IoskeleyMonoTerm
html = html.replaceAll('"Space Grotesk", system-ui, sans-serif', '"IoskeleyMonoTerm", monospace');
html = html.replaceAll('"Space Grotesk", sans-serif', '"IoskeleyMonoTerm", monospace');
html = html.replaceAll("'Space Grotesk', sans-serif", "'IoskeleyMonoTerm', monospace");
html = html.replaceAll("'Space Grotesk',sans-serif", "'IoskeleyMonoTerm', monospace");
html = html.replaceAll('"JetBrains Mono", monospace', '"IoskeleyMonoTerm", monospace');
html = html.replaceAll("'JetBrains Mono', monospace", "'IoskeleyMonoTerm', monospace");
html = html.replaceAll("'JetBrains Mono',monospace", "'IoskeleyMonoTerm', monospace");
html = html.replaceAll('"Space Grotesk"', '"IoskeleyMonoTerm"');
html = html.replaceAll("'Space Grotesk'", "'IoskeleyMonoTerm'");
html = html.replaceAll('"JetBrains Mono"', '"IoskeleyMonoTerm"');
html = html.replaceAll("'JetBrains Mono'", "'IoskeleyMonoTerm'");

// 3. Add the 3-card Classical Engraving Showcase Section matching the Zuse reference screenshot
const marqueeMarker = '<div class="marquee" aria-hidden="true"><div class="marquee-track"><span>Privacy continuum</span><span>Private EVM</span><span>XMR base layer</span><span>FCMP++</span><span>Bulletproofs++</span><span>Stealth addresses</span><span>Privacy continuum</span><span>Private EVM</span><span>XMR base layer</span><span>FCMP++</span><span>Bulletproofs++</span><span>Stealth addresses</span></div></div>';

const showcaseSection = `
    <!-- Classical Engraving Continuum Showcase (Black & White Stipple/Halftone Engravings) -->
    <div id="art-showcase" class="section" style="background:#080a0f; color:#ffffff; padding: 64px 24px; border-top: 1px solid #181c24; border-bottom: 1px solid #181c24;">
      <div style="max-width: 1200px; margin: 0 auto;">
        <div style="text-align: center; margin-bottom: 40px;">
          <div style="font-size: 11px; font-weight: 700; letter-spacing: 0.22em; text-transform: uppercase; color: #8e94a0; margin-bottom: 14px;">
            HOW SERAPH OPERATES
          </div>
          <h2 style="font-size: clamp(26px, 4vw, 44px); font-weight: 700; color: #ffffff; letter-spacing: -0.02em; line-height: 1.15; margin: 0 auto; max-width: 840px;">
            One continuum. Dual EVMs. Zero lost privacy.
          </h2>
        </div>

        <div class="art-cards-grid" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 24px;">
          <!-- Card 1: Winged Pegasus -->
          <div class="art-card" style="background: #0d1017; border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 14px; display: flex; flex-direction: column; transition: transform 0.2s ease, border-color 0.2s ease;">
            <div style="width: 100%; border-radius: 10px; overflow: hidden; background: #000000; aspect-ratio: 3/4;">
              <img src="assets/art-pegasus-bw.jpg" alt="Shield into Anonymity Set" style="width: 100%; height: 100%; object-fit: cover; display: block;" loading="lazy">
            </div>
            <div style="margin-top: 16px; display: flex; align-items: baseline; gap: 10px; padding: 4px 6px;">
              <span style="font-size: 13px; font-weight: 700; color: #71717a;">01</span>
              <span style="font-size: 15px; font-weight: 600; color: #f4f4f5; letter-spacing: -0.01em;">Shield assets into the anonymity set</span>
            </div>
          </div>

          <!-- Card 2: Celestial Observatory / Temple -->
          <div class="art-card" style="background: #0d1017; border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 14px; display: flex; flex-direction: column; transition: transform 0.2s ease, border-color 0.2s ease;">
            <div style="width: 100%; border-radius: 10px; overflow: hidden; background: #000000; aspect-ratio: 3/4;">
              <img src="assets/art-temple-bw.jpg" alt="Execute on Dual Private EVMs" style="width: 100%; height: 100%; object-fit: cover; display: block;" loading="lazy">
            </div>
            <div style="margin-top: 16px; display: flex; align-items: baseline; gap: 10px; padding: 4px 6px;">
              <span style="font-size: 13px; font-weight: 700; color: #71717a;">02</span>
              <span style="font-size: 15px; font-weight: 600; color: #f4f4f5; letter-spacing: -0.01em;">Execute on dual confidential EVMs</span>
            </div>
          </div>

          <!-- Card 3: Sculpted Hands Exchanging Orb -->
          <div class="art-card" style="background: #0d1017; border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 14px; display: flex; flex-direction: column; transition: transform 0.2s ease, border-color 0.2s ease;">
            <div style="width: 100%; border-radius: 10px; overflow: hidden; background: #000000; aspect-ratio: 3/4;">
              <img src="assets/art-hands-bw.jpg" alt="Settle Zero-Knowledge Proofs" style="width: 100%; height: 100%; object-fit: cover; display: block;" loading="lazy">
            </div>
            <div style="margin-top: 16px; display: flex; align-items: baseline; gap: 10px; padding: 4px 6px;">
              <span style="font-size: 13px; font-weight: 700; color: #71717a;">03</span>
              <span style="font-size: 15px; font-weight: 600; color: #f4f4f5; letter-spacing: -0.01em;">Settle with mathematical ZK proofs</span>
            </div>
          </div>
        </div>
      </div>
    </div>
`;

if (html.includes(marqueeMarker)) {
  html = html.replace(marqueeMarker, `${marqueeMarker}\n${showcaseSection}`);
} else {
  console.warn("Could not find marquee marker, appending before #privacy");
  html = html.replace('<div id="privacy"', `${showcaseSection}\n<div id="privacy"`);
}

fs.writeFileSync(indexPath, html, 'utf8');
console.log('Successfully updated website/index.html with IoskeleyMonoTerm font and B&W engraving showcase!');
