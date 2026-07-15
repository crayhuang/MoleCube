# MoleCube commercial open source distribution

MoleCube may be sold, but it is distributed under GPL-3.0 because it includes and
uses Mole, which is GPL-3.0 software.

## Release obligations

For every distributed DMG:

1. Include `LICENSE` and `NOTICE` in the mounted disk image.
2. Identify Mole as an upstream project by tw93 and contributors.
3. Publish the corresponding source for the exact release tag at
   `https://github.com/crayhuang/MoleCube`.
4. Include the UI source, the bundled Mole source, all modifications, and the build
   scripts needed to produce the distributed application.
5. Keep the source available for as long as the matching object-code release is
   offered, and show a clear source link next to the DMG download.
6. Do not add terms that prevent recipients from running, modifying, or
   redistributing the GPL-covered work.

## Recommended release flow

1. Commit the release source and create a version tag.
2. Build a signed, notarized universal archive from that tag.
3. Run `apps/MoleCubeMac/Scripts/create_dmg.sh` using that archive.
4. Upload the DMG and its source link together in the same GitHub Release.
5. Update the website's DMG link only after the Release is public.

`create_dmg.sh` intentionally refuses a dirty checkout. This prevents a binary from
being published without a reproducible corresponding source revision.
