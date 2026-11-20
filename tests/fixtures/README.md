# File upload regression

Serve this directory over HTTP and open `file-upload.html` in Kelpie. On
desktop, check both Safari and Chrome on macOS, plus Windows and Linux. On
mobile, use the Files picker on iOS or Android. Use two small plain-text
files with distinct contents.

1. Click or tap **Upload**, choose one file, and check that the page prints
   its name and contents. The button opens a hidden file input, as many
   upload forms do.
2. Open **Upload** again and cancel. Check that the picker closes without
   adding a file. Reopen and choose the other file to verify recovery.
3. Use **Multiple files** to choose both files and verify that the page prints
   both names and contents.
