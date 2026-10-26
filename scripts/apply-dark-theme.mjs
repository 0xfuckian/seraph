import fs from 'node:fs';
import path from 'node:path';

const htmlPath = path.resolve('website/index.html');
let html = fs.readFileSync(htmlPath, 'utf8');

// 1. Update Hero 3D cube colors
html = html.replace(
  `    const black = new THREE.MeshBasicMaterial({ color: 0x0e1012 });
    const grey = new THREE.MeshBasicMaterial({ color: 0x8a8f98 });
    const white = new THREE.MeshBasicMaterial({ color: 0xffffff });
    // BoxGeometry face order: +x (right), -x, +y (top), -y, +z (left), -z
    cube.add(new THREE.Mesh(new THREE.BoxGeometry(size, size, size), [grey, black, white, black, black, black]));

    // Hairline around the white top face so it stays visible on the white page
    const h = size / 2, t = 0.04;
    const hairline = new THREE.MeshBasicMaterial({ color: 0xd9dadd });`,
  `    const darkFace = new THREE.MeshBasicMaterial({ color: 0x181e2b });
    const grey = new THREE.MeshBasicMaterial({ color: 0x8a8f98 });
    const white = new THREE.MeshBasicMaterial({ color: 0xffffff });
    // BoxGeometry face order: +x (right), -x, +y (top), -y, +z (left), -z
    cube.add(new THREE.Mesh(new THREE.BoxGeometry(size, size, size), [grey, darkFace, white, darkFace, darkFace, darkFace]));

    // Hairline around the top face for crisp contrast against deep black
    const h = size / 2, t = 0.04;
    const hairline = new THREE.MeshBasicMaterial({ color: 0x3b82f6 });`
);

// 2. Update Ring Stage Level 0 color from black (0x0e1012) to glowing white (0xffffff)
html = html.replace(
  `{ label: 'Level 0 · Transparent', hex: 0x0e1012 }`,
  `{ label: 'Level 0 · Transparent', hex: 0xffffff }`
);

// 3. Update Architecture node network (blue web to white)
html = html.replace(
  `    const points = new THREE.Points(new THREE.BufferGeometry().setFromPoints(pts), new THREE.PointsMaterial({ color: 0x2f4cff, size: 0.06 }));
    const linePts = [];
    for (let i = 0; i < N; i++) {
      for (let j = i + 1; j < N; j++) {
        if (pts[i].distanceTo(pts[j]) < 1.5) linePts.push(pts[i], pts[j]);
      }
    }
    const lines = new THREE.LineSegments(
      new THREE.BufferGeometry().setFromPoints(linePts),
      new THREE.LineBasicMaterial({ color: 0x2f4cff, transparent: true, opacity: 0.25 })
    );`,
  `    const points = new THREE.Points(new THREE.BufferGeometry().setFromPoints(pts), new THREE.PointsMaterial({ color: 0xffffff, size: 0.07 }));
    const linePts = [];
    for (let i = 0; i < N; i++) {
      for (let j = i + 1; j < N; j++) {
        if (pts[i].distanceTo(pts[j]) < 1.5) linePts.push(pts[i], pts[j]);
      }
    }
    const lines = new THREE.LineSegments(
      new THREE.BufferGeometry().setFromPoints(linePts),
      new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.35 })
    );`
);

// 4. Update Roadmap particle field (dust specks from black to luminous white)
html = html.replace(
  `const field = new THREE.Points(pGeo, new THREE.PointsMaterial({ color: 0x0e1012, size: 0.03, transparent: true, opacity: 0.55 }));`,
  `const field = new THREE.Points(pGeo, new THREE.PointsMaterial({ color: 0xffffff, size: 0.045, transparent: true, opacity: 0.85 }));`
);

// 5. Integrate art-pool-bw.jpg in #privacy-pool
const poolCardHtml = `      <!-- Privacy Pool Hero Engraving: Fountain of Anonymity -->
      <div class="reveal" style="margin-bottom: 24px; background: #0d111a; border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 20px; display: flex; flex-direction: row; gap: 24px; align-items: center; flex-wrap: wrap;">
        <div style="width: 140px; min-width: 140px; max-width: 160px; border-radius: 10px; overflow: hidden; background: #000000; aspect-ratio: 3/4; flex-shrink: 0;">
          <img src="assets/art-pool-bw.jpg" alt="Privacy Pool Sanctuary" style="width: 100%; height: 100%; object-fit: cover; display: block;" loading="lazy">
        </div>
        <div style="flex: 1; min-width: 240px;">
          <div style="display: flex; align-items: baseline; gap: 10px; margin-bottom: 8px;">
            <span style="font-size: 13px; font-weight: 700; color: #71717a;">01B</span>
            <span style="font-size: 12px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: #9da4b2;">Cryptographic Sanctuary</span>
          </div>
          <h3 style="font-size: 20px; font-weight: 700; color: #ffffff; margin: 0 0 8px 0; letter-spacing: -0.01em;">
            The Fountain of Anonymity
          </h3>
          <p style="font-size: 13px; line-height: 1.6; color: #9da4b2; margin: 0;">
            Deposit public assets to mint zero-knowledge note commitments into the 2<sup>20</sup> Merkle ring buffer. Spend anonymously via deterministic nullifiers with zero on-chain linkability.
          </p>
        </div>
      </div>
`;
if (!html.includes('art-pool-bw.jpg')) {
  html = html.replace(
    `<div class="priv-dock">`,
    poolCardHtml + `      <div class="priv-dock">`
  );
}

// 6. Integrate art-ouroboros-bw.jpg in #tokenomics
const tokenCardHtml = `      <!-- Tokenomics Hero Engraving: Ouroboros & Algorithmic Equilibrium -->
      <div class="reveal" style="margin-bottom: 24px; background: #0d111a; border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 20px; display: flex; flex-direction: row; gap: 24px; align-items: center; flex-wrap: wrap;">
        <div style="width: 140px; min-width: 140px; max-width: 160px; border-radius: 10px; overflow: hidden; background: #000000; aspect-ratio: 3/4; flex-shrink: 0;">
          <img src="assets/art-ouroboros-bw.jpg" alt="Ouroboros Equilibrium" style="width: 100%; height: 100%; object-fit: cover; display: block;" loading="lazy">
        </div>
        <div style="flex: 1; min-width: 240px;">
          <div style="display: flex; align-items: baseline; gap: 10px; margin-bottom: 8px;">
            <span style="font-size: 13px; font-weight: 700; color: #71717a;">06</span>
            <span style="font-size: 12px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: #9da4b2;">Mathematical Scarcity</span>
          </div>
          <h3 style="font-size: 20px; font-weight: 700; color: #ffffff; margin: 0 0 8px 0; letter-spacing: -0.01em;">
            The Ouroboros &amp; Algorithmic Equilibrium
          </h3>
          <p style="font-size: 13px; line-height: 1.6; color: #9da4b2; margin: 0;">
            A strict 100,000,000 SER cap with zero inflation. On-chain DEX sells burn 50% of the 1% fee directly into the null address, maintaining deflationary pressure as protocol volume scales.
          </p>
        </div>
      </div>
`;
if (!html.includes('art-ouroboros-bw.jpg')) {
  html = html.replace(
    `<div class="token-two reveal">`,
    tokenCardHtml + `      <div class="token-two reveal">`
  );
}

// 7. Integrate art-roadmap-bw.jpg in #roadmap
const roadmapCardHtml = `      <!-- Roadmap Hero Engraving: The Celestial Navigator -->
      <div class="reveal" style="margin-bottom: 32px; background: #0d111a; border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 20px; display: flex; flex-direction: row; gap: 24px; align-items: center; flex-wrap: wrap;">
        <div style="width: 140px; min-width: 140px; max-width: 160px; border-radius: 10px; overflow: hidden; background: #000000; aspect-ratio: 3/4; flex-shrink: 0;">
          <img src="assets/art-roadmap-bw.jpg" alt="Celestial Roadmap Navigator" style="width: 100%; height: 100%; object-fit: cover; display: block;" loading="lazy">
        </div>
        <div style="flex: 1; min-width: 240px;">
          <div style="display: flex; align-items: baseline; gap: 10px; margin-bottom: 8px;">
            <span style="font-size: 13px; font-weight: 700; color: #71717a;">07</span>
            <span style="font-size: 12px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: #9da4b2;">Multi-Phase Expansion</span>
          </div>
          <h3 style="font-size: 20px; font-weight: 700; color: #ffffff; margin: 0 0 8px 0; letter-spacing: -0.01em;">
            The Passage Across Epochs
          </h3>
          <p style="font-size: 13px; line-height: 1.6; color: #9da4b2; margin: 0;">
            From the live EVM core on Base Sepolia through dedicated XMR EVM execution to sovereign Rust settlement with FCMP++ full-chain membership proofs.
          </p>
        </div>
      </div>
`;
if (!html.includes('art-roadmap-bw.jpg')) {
  html = html.replace(
    `<div class="roadmap reveal">`,
    roadmapCardHtml + `      <div class="roadmap reveal">`
  );
}

// 8. Integrate art-curve-bw.jpg in #view-launch
const curveCardHtml = `      <!-- Launchpad Hero Engraving: Archimedean Bonding Spiral -->
      <div class="reveal" style="margin-bottom: 24px; background: #0d111a; border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 20px; display: flex; flex-direction: row; gap: 24px; align-items: center; flex-wrap: wrap;">
        <div style="width: 140px; min-width: 140px; max-width: 160px; border-radius: 10px; overflow: hidden; background: #000000; aspect-ratio: 3/4; flex-shrink: 0;">
          <img src="assets/art-curve-bw.jpg" alt="Archimedean Bonding Spiral" style="width: 100%; height: 100%; object-fit: cover; display: block;" loading="lazy">
        </div>
        <div style="flex: 1; min-width: 240px;">
          <div style="display: flex; align-items: baseline; gap: 10px; margin-bottom: 8px;">
            <span style="font-size: 13px; font-weight: 700; color: #71717a;">08</span>
            <span style="font-size: 12px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: #9da4b2;">Algorithmic Discovery</span>
          </div>
          <h3 style="font-size: 20px; font-weight: 700; color: #ffffff; margin: 0 0 8px 0; letter-spacing: -0.01em;">
            The Archimedean Bonding Spiral
          </h3>
          <p style="font-size: 13px; line-height: 1.6; color: #9da4b2; margin: 0;">
            Fair-launch token discovery governed by constant-product bonding curves. 100% of initial liquidity locks into verified smart contracts with zero team premine or insider allocations.
          </p>
        </div>
      </div>
`;
if (!html.includes('art-curve-bw.jpg')) {
  html = html.replace(
    `<div class="lp-toolbar">`,
    curveCardHtml + `      <div class="lp-toolbar">`
  );
}

// 9. Integrate art-council-bw.jpg in #governance
const councilCardHtml = `      <!-- Governance Hero Engraving: Anonymous Council of Guardians -->
      <div class="reveal" style="margin-bottom: 24px; background: #0d111a; border: 1px solid rgba(255,255,255,0.08); border-radius: 16px; padding: 20px; display: flex; flex-direction: row; gap: 24px; align-items: center; flex-wrap: wrap;">
        <div style="width: 140px; min-width: 140px; max-width: 160px; border-radius: 10px; overflow: hidden; background: #000000; aspect-ratio: 3/4; flex-shrink: 0;">
          <img src="assets/art-council-bw.jpg" alt="Anonymous Governance Council" style="width: 100%; height: 100%; object-fit: cover; display: block;" loading="lazy">
        </div>
        <div style="flex: 1; min-width: 240px;">
          <div style="display: flex; align-items: baseline; gap: 10px; margin-bottom: 8px;">
            <span style="font-size: 13px; font-weight: 700; color: #71717a;">09</span>
            <span style="font-size: 12px; font-weight: 700; letter-spacing: 0.16em; text-transform: uppercase; color: #9da4b2;">Decentralized Sovereignty</span>
          </div>
          <h3 style="font-size: 20px; font-weight: 700; color: #ffffff; margin: 0 0 8px 0; letter-spacing: -0.01em;">
            The Anonymous Council of Guardians
          </h3>
          <p style="font-size: 13px; line-height: 1.6; color: #9da4b2; margin: 0;">
            Zero-knowledge ballot tallies proving quorum and voting weights without exposing voter balances, transaction graphs, or delegate identities.
          </p>
        </div>
      </div>
`;
if (!html.includes('art-council-bw.jpg')) {
  html = html.replace(
    `<div class="section-header" style="margin-top:24px;">`,
    councilCardHtml + `      <div class="section-header" style="margin-top:24px;">`
  );
}

fs.writeFileSync(htmlPath, html, 'utf8');
console.log('✔ Dark theme and all 5 new artworks applied to website/index.html');
