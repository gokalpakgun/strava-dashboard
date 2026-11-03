# Tempo brand · 4 November 2026

The approved mark is now two glossy, separated parallelograms: silver/white on the lower left, blue/cyan/mint on the upper right. mark.svg is its clean scalable implementation, matching the supplied Glossy Dual Parallelogram Logo.png. The icon and web canvas are pure black (#000000), with no grain or external neon glow. The mark occupies roughly 70% of the icon width.

Run node branding/tempo/build.cjs. It uses the existing worker sharp dependency or TEMPO_SHARP_PATH. The generator updates every opaque AppIcon size, app-icon.png, the opaque in-app mark, the transparent launch mark, the two transparent launch layers and the web SVG. Do not modify raster outputs independently. Keep AppIcon's Contents.json mapping intact.

TempoBrandMark is shared by the generated athlete/profile card and other in-app branding. The launch assembles the two layers using a single finite perspective animation; Reduce Motion uses the static mark. Its black launch background is shared with the system launch screen. The launch has no text, spinner or looping animation, and does not delay account loading.
