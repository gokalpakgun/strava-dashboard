// Yeni çift paralelkenar işaretinden tüm platform varlıkları birlikte üretilir.
const fs = require('fs');
const path = require('path');
let sharp;
try { sharp = require('sharp'); } catch {
  sharp = require(process.env.TEMPO_SHARP_PATH || '../../worker/node_modules/sharp');
}
const root = path.resolve(__dirname, '../..');
const mark = fs.readFileSync(path.join(__dirname, 'mark.svg'), 'utf8');
const blackMark = mark.replace('<defs>', '<rect width="1254" height="1254" fill="#000000"/><defs>');
const assetRoot = path.join(root, 'ios/TempoHealth/Sources/Assets.xcassets');
async function writeImageSet(name, svg, opaque = false) {
  const dir = path.join(assetRoot, name + '.imageset');
  fs.mkdirSync(dir, { recursive: true });
  let image = sharp(Buffer.from(svg)).resize(768, 768);
  if (opaque) image = image.flatten({ background: '#000000' }).removeAlpha();
  await image.png().toFile(path.join(dir, name + '.png'));
  fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify({
    images: [{ filename: name + '.png', idiom: 'universal', scale: '1x' }],
    info: { author: 'xcode', version: 1 }
  }, null, 2) + '\n');
}
(async () => {
  const icons = path.join(assetRoot, 'AppIcon.appiconset');
  const catalog = JSON.parse(fs.readFileSync(path.join(icons, 'Contents.json'), 'utf8'));
  for (const item of catalog.images) {
    const n = Number(item.size.split('x')[0]) * Number(item.scale.replace('x', ''));
    await sharp(Buffer.from(blackMark)).resize(n, n).flatten({ background: '#000000' }).removeAlpha().png().toFile(path.join(icons, item.filename));
  }
  await writeImageSet('TempoLogo', blackMark, true);
  await writeImageSet('TempoLaunchMark', mark);
  // Ortak koordinatlar, parçaların animasyon sonunda tam birleşmesini sağlar.
  await writeImageSet('TempoLaunchLeading', mark.replace(/<g id="trailing">[\s\S]*?<\/g>/, ''));
  await writeImageSet('TempoLaunchTrailing', mark.replace(/<g id="leading">[\s\S]*?<\/g>/, ''));
  fs.copyFileSync(path.join(icons, 'AppIcon-1024.png'), path.join(__dirname, 'app-icon.png'));
  for (const dir of ['public', 'worker/public']) if (fs.existsSync(path.join(root, dir))) {
    fs.writeFileSync(path.join(root, dir, 'tempo-mark.svg'), blackMark);
  }
  console.log('Tempo brand: 9 black icons, shared logo, 2 launch layers and web mark generated.');
})().catch(error => { console.error(error); process.exitCode = 1; });
