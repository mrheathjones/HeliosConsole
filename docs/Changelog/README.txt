Changelog entries are dated files (MM_DD_YYYY.txt) in this directory.

To append an entry for today from the repo root:

  echo "- Your change description here." >> "docs/Changelog/$(date +"%m_%d_%Y").txt"

Or run the helper script, which creates the dated file if needed:

  ./scripts/heliosChangeLog.sh
