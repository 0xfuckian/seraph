import fs from 'node:fs';
import path from 'node:path';

// 1. Update website/brand-mockup.html
const brandPath = path.resolve('website/brand-mockup.html');
if (fs.existsSync(brandPath)) {
  let brandHtml = fs.readFileSync(brandPath, 'utf8');
  
  const fontFaceDeclaration = `  <!-- Typography: IoskeleyMonoTerm -->
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
  </style>`;

  brandHtml = brandHtml.replace(/<link href="https:\/\/fonts\.googleapis\.com\/css2\?family=Space\+Grotesk[^"]*" rel="stylesheet">/i, fontFaceDeclaration);
  brandHtml = brandHtml.replaceAll('"Space Grotesk"', '"IoskeleyMonoTerm"');
  brandHtml = brandHtml.replaceAll("'Space Grotesk'", "'IoskeleyMonoTerm'");
  brandHtml = brandHtml.replaceAll('"JetBrains Mono"', '"IoskeleyMonoTerm"');
  brandHtml = brandHtml.replaceAll("'JetBrains Mono'", "'IoskeleyMonoTerm'");
  
  fs.writeFileSync(brandPath, brandHtml, 'utf8');
  console.log('✔ Updated website/brand-mockup.html');
}

// 2. Update website/presale-app/src/styles.css
const presaleCssPath = path.resolve('website/presale-app/src/styles.css');
if (fs.existsSync(presaleCssPath)) {
  let presaleCss = fs.readFileSync(presaleCssPath, 'utf8');
  const fontFaceCss = `@font-face {
  font-family: 'IoskeleyMonoTerm';
  src: url('/fonts/IoskeleyMonoTerm-Regular.ttf') format('truetype');
  font-weight: 100 900;
  font-style: normal;
  font-display: swap;
}
*, *::before, *::after {
  font-family: 'IoskeleyMonoTerm', monospace !important;
}
`;
  if (!presaleCss.includes('IoskeleyMonoTerm')) {
    presaleCss = fontFaceCss + presaleCss;
  }
  presaleCss = presaleCss.replaceAll('"Space Grotesk"', '"IoskeleyMonoTerm"');
  presaleCss = presaleCss.replaceAll("'Space Grotesk'", "'IoskeleyMonoTerm'");
  presaleCss = presaleCss.replaceAll('"JetBrains Mono"', '"IoskeleyMonoTerm"');
  presaleCss = presaleCss.replaceAll("'JetBrains Mono'", "'IoskeleyMonoTerm'");

  fs.writeFileSync(presaleCssPath, presaleCss, 'utf8');
  console.log('✔ Updated website/presale-app/src/styles.css');
}

// 3. Update website/dist/assets/index-BLmzob2D.css
const distCssPath = path.resolve('website/dist/assets/index-BLmzob2D.css');
if (fs.existsSync(distCssPath)) {
  let distCss = fs.readFileSync(distCssPath, 'utf8');
  const fontFaceCss = `@font-face{font-family:'IoskeleyMonoTerm';src:url('/fonts/IoskeleyMonoTerm-Regular.ttf') format('truetype');font-weight:100 900;font-style:normal;font-display:swap}*,*::before,*::after{font-family:'IoskeleyMonoTerm',monospace !important}`;
  if (!distCss.includes('IoskeleyMonoTerm')) {
    distCss = fontFaceCss + distCss;
  }
  distCss = distCss.replaceAll('Space Grotesk', 'IoskeleyMonoTerm');
  distCss = distCss.replaceAll('JetBrains Mono', 'IoskeleyMonoTerm');

  fs.writeFileSync(distCssPath, distCss, 'utf8');
  console.log('✔ Updated website/dist/assets/index-BLmzob2D.css');
}
