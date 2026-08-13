# GeoNames postal-code data attribution

The checked-in `data/PH.txt` snapshot is from the GeoNames Philippines
postal-code export:

- Source: <https://download.geonames.org/export/zip/PH.zip>
- Publisher: © GeoNames, <https://www.geonames.org/>
- Licence: Creative Commons Attribution 4.0,
  <https://creativecommons.org/licenses/by/4.0/>
- Retrieved: 2026-08-13 Asia/Manila
- Source `Last-Modified`: Wed, 12 Aug 2026 02:14:22 GMT
- Retrieved archive SHA-256 (refresh provenance; the checked-in `PH.txt` hash
  below is the repository-enforced integrity anchor):
  `7027cac6b35e5f669b73a5bda14219fc1c0c6c14d1cdd45032fef35a43fe3562`
- Checked-in `PH.txt` SHA-256:
  `bf5e6253192fafa2885a57e47450d313d51fcf6c9454ea39ff952f31cd4919d2`

The snapshot is redistributed unmodified as `PH.txt`. Buwiz transforms its
postal code, place name, region, and province columns into an offline Zig
suggestion catalogue. Latitude, longitude, and accuracy fields are not exposed
by the Tax Profile UI.

GeoNames supplies the data without warranty or representation of accuracy,
timeliness, or completeness. Buwiz therefore does not use catalogue membership
as validation: any syntactically valid four-digit Philippine ZIP remains
enterable.
