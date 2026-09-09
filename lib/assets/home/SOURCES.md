# Approved home assets

Inspected and downloaded 2026-09-09 from the user's approved Figma frame:
https://www.figma.com/design/xgUd2FZFUscBxVEvMOT97N/Untitled?node-id=18-16

All image/icon assets are exact Figma downloads. No replacement destination artwork
was generated. Only this frame and its descendants were read; nothing was written to Figma.

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
