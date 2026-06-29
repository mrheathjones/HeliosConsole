#!/bin/bash
#
# heliosChangeLog.sh — append a dated changelog entry for Helios Console.
# Writes to docs/Changelog/<MM_DD_YYYY>.txt within the repo (override with
# CHANGELOG_DIR=/some/path).

set -euo pipefail

# Resolve repo root relative to this script so it works on any machine.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." &> /dev/null && pwd)"

changelogFilePath="${CHANGELOG_DIR:-${REPO_ROOT}/docs/Changelog}"
changelogDate="$(date +"%m_%d_%Y")"
changelogFile="${changelogDate}.txt"

makeChangeLogDir() {
	mkdir -p "${changelogFilePath}"
}

makeChangeLogFile() {
	if [[ ! -f "${changelogFilePath}/${changelogFile}" ]]; then
		touch "${changelogFilePath}/${changelogFile}"
	fi
}

writeChangeLogData() {
	local changeLogData="$1"
	echo "${changeLogData}" >> "${changelogFilePath}/${changelogFile}"
}

makeChangeLogDir
makeChangeLogFile
writeChangeLogData "- Helios Console version: 1.0 Build: a00201."
writeChangeLogData "- Resolved Scaling issue on Dashboard items."
