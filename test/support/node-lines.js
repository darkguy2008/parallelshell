'use strict';
const NODE_RELEASES_URL = 'https://nodejs.org/dist/index.json';
const CI_RUNNERS = { 'ubuntu-latest': 'linux-x64', 'macos-latest': 'osx-arm64-tar', 'windows-latest': 'win-x64-zip' };

const majorOf = release => Number(release.version.slice(1).split('.')[0]);

async function supportedMajors(file) {
    const releases = (await (await fetch(NODE_RELEASES_URL)).json()).filter(release => !file || release.files.includes(file));
    const majors = new Set(releases.filter(release => release.lts).map(majorOf));
    majors.add(majorOf(releases[0]));
    return [...majors].sort((a, b) => a - b);
}

async function ciMatrix() {
    const runs = await Promise.all(Object.keys(CI_RUNNERS).map(async os => (await supportedMajors(CI_RUNNERS[os])).map(node => ({ os, node }))));
    return runs.flat();
}

module.exports = { supportedMajors };

if (require.main === module) ciMatrix().then(matrix => console.log(JSON.stringify(matrix)));
