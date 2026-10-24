// Pure vector rasterization: icon, launch and web use the same approved T.
const fs=require('fs');
const path=require('path');
let sharp;
try { sharp=require('sharp'); } catch { if(!process.env.TEMPO_SHARP_PATH) throw new Error('Install sharp or set TEMPO_SHARP_PATH to its package directory.'); sharp=require(process.env.TEMPO_SHARP_PATH); }
const root=path.resolve(__dirname,'../..');
const mark=fs.readFileSync(path.join(__dirname,'mark.svg'),'utf8');
const icon=mark.replace('fill="none">','fill="none"><rect width="1254" height="1254" fill="#071B38"/>').replace('  <path fill="url(#blue)"','  <g transform="translate(62.7 62.7) scale(.9)"><path fill="url(#blue)"').replace('</svg>','</g></svg>');
(async()=>{
  const icons=path.join(root,'ios/TempoHealth/Sources/Assets.xcassets/AppIcon.appiconset');
  const catalog=JSON.parse(fs.readFileSync(path.join(icons,'Contents.json'),'utf8'));
  for(const item of catalog.images){const n=Number(item.size.split('x')[0])*Number(item.scale.replace('x','')); await sharp(Buffer.from(icon)).resize(n,n).flatten({background:'#071B38'}).removeAlpha().png().toFile(path.join(icons,item.filename));}
  await sharp(Buffer.from(mark)).resize(768,768).png().toFile(path.join(root,'ios/TempoHealth/Sources/Assets.xcassets/TempoLaunchMark.imageset/TempoLaunchMark.png'));
  fs.copyFileSync(path.join(icons,'AppIcon-1024.png'),path.join(__dirname,'app-icon.png'));
  // Existing website assets also receive the same mark.
  for(const dir of ['public','worker/public'])if(fs.existsSync(path.join(root,dir))){
    fs.writeFileSync(path.join(root,dir,'tempo-mark.svg'),mark);
  }
})();
