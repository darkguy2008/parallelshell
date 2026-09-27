'use strict';
const NODE_RELEASES_URL = 'https://nodejs.org/dist/index.json';
const CI_RUNNERS = { 'ubuntu-latest': 'linux-x64', 'macos-latest': 'osx-arm64-tar', 'windows-latest': 'win-x64-zip' };

const majorOf = release => Number(release.version.slice(1).split('.')[0]);

async function nodeReleases() {
    const response = await fetch(NODE_RELEASES_URL);
    return response.json();
}

function supportedMajors(releases, file) {
    const available = releases.filter(release => release.files.includes(file));
    const majors = new Set(available.filter(release => release.lts).map(majorOf));
    majors.add(majorOf(available[0]));
    return [...majors].sort((a, b) => a - b);
}

async function ciMatrix() {
    const releases = await nodeReleases();
    return Object.entries(CI_RUNNERS).flatMap(([os, file]) => supportedMajors(releases, file).map(node => ({ os, node })));
}

module.exports = { nodeReleases, supportedMajors };

if (require.main === module) ciMatrix().then(matrix => console.log(JSON.stringify(matrix)));
