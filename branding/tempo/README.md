# Tempo T assets

The approved green/blue T is maintained in mark.svg: app-accent green, brighter blue and matched soft contact shading along both ribbon seams. The background is a uniform #071B35; no texture, grain, neon or glow is used.

Run node branding/tempo/build.cjs with sharp installed, or set TEMPO_SHARP_PATH to its package directory. The generator updates all opaque AppIcon sizes, branding/app-icon.png, both transparent in-app image sets and the web SVG from the same vector. Do not edit the raster outputs independently. Keep the AppIcon Contents.json mapping intact.

TempoBrandMark is also used by TempoProfileShareArtwork, so both profile-card preview and exported PNG receive the same transparent mark. Launch animation uses that shared mark, with one short focus/scale entrance, no text, no spinner and a reduced-motion alternative.
