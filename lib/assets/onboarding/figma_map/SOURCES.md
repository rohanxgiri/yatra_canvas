# Figma map onboarding assets

Downloaded from YatraCanvas Figma file `xgUd2FZFUscBxVEvMOT97N`, node `73:90`,
on 2026-09-18 using the official Figma MCP asset URLs.

- `map_albert_hall_pin.png`: node 73:113
- `map_jal_mahal_pin.png`: node 73:114
- `map_hawa_mahal_pin.png`: node 73:115
- `map_route.svg`: node 73:116
- `map_route_node.svg`: nodes 73:95, 73:98, 73:101, 73:104, 73:107
- `map_title_glow.svg`: node 73:110 source asset; its two endpoint nodes are
  rendered with `map_route_node.svg` because Flutter SVG does not support the
  source's no-op filter elements
- `map_glow_left.svg`: node 73:92 source asset
- `map_glow_right.svg`: node 73:93 source asset
- `map_glow_bottom.svg`: node 73:94 source asset

Flutter SVG does not support the source glow assets' Gaussian blur filters. The
three glow SVGs are retained as source references; the runtime renders their
elliptical geometry with clipped `ImageFiltered` blur layers.
