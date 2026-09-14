# Approved home assets

Inspected and downloaded 2026-09-09 from the user's approved Figma frame:
https://www.figma.com/design/xgUd2FZFUscBxVEvMOT97N/Untitled?node-id=18-16

The approved Home image/icon assets below are exact Figma downloads. No replacement destination artwork
was generated. Only this frame and its descendants were read; nothing was written to Figma.

## Additional onboarding artwork

`journey_editorial.png` is custom image-generated artwork for the redesigned onboarding story, added September 2026. It is not a Figma download and is not used to replace any Home or Explore image. All story pages crop the same illustration, with native UI text outside it.

Generation brief: square premium editorial Indian travel illustration; sandstone palace, temple riverside ghat, cafe veranda, distant blue hills and a winding path; warm amber/terracotta, cream sky and travel blue; elegant painterly geometry, soft depth and a travel-journal feeling. Keep essential content in the central 75% for responsive cropping. No text, logos, numbers or UI cards.

## Approved Home downloads

### Mountain category illustration — 2026-09-13

`mountain_editorial.png` was created using the built-in image-generation tool and
copied into this asset directory. It is used for Nature Retreats and Mountain
Escapes in Explore. It is general illustrative inspiration, not a photograph of
a named attraction. The user explicitly requested an illustrative treatment.
The initial photographic draft was replaced before delivery.

Final prompt: Create a square editorial travel illustration for YatraCanvas,
using `journey_editorial.png` only as a painterly style/palette reference. Indian
Himalayan foothill valley, layered soft blue ridges, deodar trees, winding walking
path and distant river. Clearly hand-painted gouache, elegant simplified shapes,
broad visible brushwork, subtle paper texture, flat painted color and gentle depth.
Cream sky, amber morning light, muted greens and travel blues. Darker lower quarter
for white title overlays; central 75% safe for mobile cropping. No text, UI, logos,
people, palaces, temples, landmark mashups, photorealism, camera textures, lens
effects, 3D, neon or oversaturation. Request 1024 square; tool output is 1254 square.

### Figma asset provenance

| Local asset | Source within frame 18:16 |
| --- | --- |
| home_background.png | 18:17, original image fill, flipped vertically and blurred in Flutter |
| avatar.png | 18:22, avatar |
| ujjain.png | 18:46, rendered image layer with original clipped crop; replaces the previous blank fill download |
| jaipur.png | 18:24 destination instance image fill |
| varanasi.png | 18:25 destination instance image fill |
| mountains.svg, route.svg, route_pin.svg | 18:79, 18:88, 18:80 / 18:84 |
| calendar.svg, search.svg, plus.svg | 18:57, 18:66, 18:76 |
| home_selected.svg, home.svg | 18:29, 18:30 |
| discover.svg | 18:31 |
| create_circle.svg, create_vertical.svg, create_horizontal.svg | 18:36–18:38 |
| favorites.svg, profile.svg | 18:39, 18:41 |
| favorite_background.svg, favorite_filled.svg, favorite_outline.svg | destination favorite layers in 18:24 / 18:25 |
| location_outline.svg, location_center.svg | destination location-pin vectors |
| glow_top.svg, glow_left.svg, glow_right.svg | 18:18–18:20; retained as parameter references for Flutter's blur painter |

The isolated PNG exports of the selected circle and hero shading contained opaque
backdrops; they are not shipped. Native Flutter rendering uses the original vectors
and inspected gradient/opacity values instead.

The font is bundled separately as `../fonts/Inter.ttf`, from the official Google
Fonts repository `ofl/inter/Inter[opsz,wght].ttf`:
https://github.com/google/fonts/tree/main/ofl/inter
The downloaded SIL Open Font License is `../fonts/OFL.txt`. Flutter registers it as
`HomeInter` to avoid changing typography on other screens.

### Popular destination grid additions — September 2026

`udaipur.png`, `manali.png`, `goa.png`, and `rishikesh.png` were created using the built-in image-generation tool
to extend the Popular Destinations section to a 6-item 2-column grid.
They follow the exact painterly travel poster aesthetic of `jaipur.png` and `varanasi.png`, with 4:3 full-bleed
landscape framing, landmark/cultural focus, and safe lower margins for white destination typography overlays.

