// Generează iconițele aplicației (Android + iOS) dintr-un SVG 1024×1024.
// Rulare: node tool/iconita/genereaza.js tool/iconita/iconita.svg
// Necesită Playwright cu Chromium. După rulare, PNG-urile iOS trebuie convertite
// la RGB (fără canal alfa), altfel App Store le refuză.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const sursa = process.argv[2];
const radacina = path.resolve(__dirname, '../..');
const svg = fs.readFileSync(sursa, 'utf8');
// Fundalul e primul <rect> pe toată suprafața; prim-planul e restul.
const faraFundal = svg.replace(/<rect width="1024" height="1024"[^>]*\/>/, '');
const dataUrl = (s) => 'data:image/svg+xml;base64,' + Buffer.from(s).toString('base64');

async function randeaza(page, html, marime, iesire) {
  await page.setViewportSize({ width: marime, height: marime });
  await page.setContent(`<html><body style="margin:0;background:transparent">${html}</body></html>`);
  await page.waitForTimeout(50);
  fs.mkdirSync(path.dirname(iesire), { recursive: true });
  await page.screenshot({ path: iesire, omitBackground: true });
}

(async () => {
  const b = await chromium.launch();
  const page = await b.newPage();
  const img = (s, stil) => `<img src="${dataUrl(s)}" style="display:block;${stil}">`;
  const res = path.join(radacina, 'android/app/src/main/res');

  // Android vechi (< 8): pătrat cu colțuri rotunjite.
  for (const [d, m] of [['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]]) {
    await randeaza(page, img(svg, `width:${m}px;height:${m}px;border-radius:${m * 0.22}px`), m,
      `${res}/mipmap-${d}/ic_launcher.png`);
    // Android 8+: prim-planul pe 108dp, cu desenul în zona sigură de 72dp.
    const f = Math.round(m * 108 / 48);
    const v = f * 72 / 108;
    await randeaza(page, img(faraFundal, `width:${v}px;height:${v}px;margin:${(f - v) / 2}px`), f,
      `${res}/mipmap-${d}/ic_launcher_foreground.png`);
  }

  // iOS: fără transparență și fără rotunjire (le face sistemul).
  const ios = path.join(radacina, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
  const contents = JSON.parse(fs.readFileSync(path.join(ios, 'Contents.json'), 'utf8'));
  for (const i of contents.images) {
    const m = Math.round(parseFloat(i.size) * parseInt(i.scale));
    await randeaza(page, img(svg, `width:${m}px;height:${m}px`), m, path.join(ios, i.filename));
  }
  await b.close();
})();
