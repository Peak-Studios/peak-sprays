# WIP Turf Laptop Testing

This branch is unfinished and should not be treated as production-ready until it has been tested in FXServer with real players, inventory items, database migrations, NUI focus, and gang contest flows.

## Preflight

1. Import `install/install.sql`.
2. Import `install/install_gangs.sql` for the gang and turf metadata migration.
3. Ensure `ox_lib`, `oxmysql`, and `peak-sprays` in that order.
4. Run `npm install` and `npm run build` from `ui` after changing the laptop UI.
5. Confirm `fxmanifest.lua` packages `ui/dist/**/*` so the built map image is shipped.
6. Restart the resource after clearing any stale client cache.

## Test Steps

1. Run `/ganglaptop` and verify the laptop opens as a smaller centered panel with the game visible around it.
2. Close with Escape and the close button, then confirm NUI focus is released cleanly.
3. Create a gang, invite a member, change rank, kick a member, and verify permission messages are clear.
4. Save a gang spray and confirm `gang_id`, gang XP, tier, and spray count update in the database.
5. Open the laptop map and confirm the new spray appears on the packaged territory map at the expected GTA coordinate.
6. Try placing another same-gang spray within `Config.PlacementDistance` and confirm placement is blocked.
7. Try normal placement inside enemy turf and confirm the contest path is required.
8. Start a contest near an enemy spray and confirm the defender spray becomes contested, the red radius appears, and the defender gang is notified.
9. Leave the contest radius before `Config.ContestDuration` and confirm the contest fails and clears.
10. Complete a contest and confirm ownership, XP, tier, map status, and activity history update.
11. Erase a gang spray and confirm map counts, XP, tier, and activity history update.
12. Watch the NUI console and FXServer logs for Lua, SQL, or browser errors throughout the flow.

## Known WIP Notes

- The branch intentionally keeps the resource standalone with `ox_lib` and `oxmysql`; it does not add hard dependencies on `fw-core`, `fw-laptop`, or `fw-graffiti`.
- Map calibration follows the `fw-laptop` style, but final marker accuracy still needs in-game coordinate spot checks.
- Contest balance values should be tuned after live testing with the target server population.
