# Steam Workshop staging

Open the local publisher's Workshop project in RGSEditor. Its content path
points to this utility's `dist/RemoveEarthquakeScreenshake` directory, which
contains the manifest, compiled script, and matching source. The project
targets existing Workshop item `3792151950`.

Run the build before uploading, confirm the title, description, tags, content
path, and preview, then update the existing item. No copy should remain under
Majesty HD's `SDK\Mods` directory after the upload. Use Steam's subscribed item
directory for installed Workshop testing.

## Update staged October 4, 2026

Includes the matching GPL source and its native manifest `Source` registration,
allowing script-merging tools to preserve the Earthquake change. Gameplay is
unchanged. The package remains a standalone Standard mod.

Use `CHANGE_NOTES.txt` for the update notes. The existing preview is retained.
