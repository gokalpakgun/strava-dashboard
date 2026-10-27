// One clean vector source for every Tempo logo consumer.
const fs = require('fs');
const path = require('path');
let sharp;
try { sharp = require('sharp'); } catch { if (!process.env.TEMPO_SHARP_PATH) throw new Error('Install sharp or set TEMPO_SHARP_PATH to its package directory.'); sharp = require(process.env.TEMPO_SHARP_PATH); }
const root = path.resolve(__dirname, '../..');
const mark = fs.readFileSync(path.join(__dirname, 'mark.svg'), 'utf8');
const icon = mark.replace('<defs>', '<rect width="1254" height="1254" fill="#071B35"/><defs>');
(async () => {
  const assets = path.join(root, 'ios/TempoHealth/Sources/Assets.xcassets');
  const icons = path.join(assets, 'AppIcon.appiconset');
  const catalog = JSON.parse(fs.readFileSync(path.join(icons, 'Contents.json'), 'utf8'));
  for (const item of catalog.images) {
    const n = Number(item.size.split('x')[0]) * Number(item.scale.replace('x', ''));
    await sharp(Buffer.from(icon)).resize(n, n).flatten({ background: '#071B35' }).removeAlpha().png().toFile(path.join(icons, item.filename));
  }
  const transparent = await sharp(Buffer.from(mark)).resize(768, 768).png().toBuffer();
  fs.writeFileSync(path.join(assets, 'TempoLaunchMark.imageset/TempoLaunchMark.png'), transparent);
  fs.writeFileSync(path.join(assets, 'TempoLogo.imageset/TempoLogo.png'), transparent);
  fs.copyFileSync(path.join(icons, 'AppIcon-1024.png'), path.join(__dirname, 'app-icon.png'));
  for (const dir of ['public', 'worker/public']) if (fs.existsSync(path.join(root, dir))) {
    fs.writeFileSync(path.join(root, dir, 'tempo-mark.svg'), mark);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
