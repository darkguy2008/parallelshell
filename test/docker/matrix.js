#!/usr/bin/env node
'use strict';
const { spawn } = require('child_process');
const path = require('path');

const NODE_RELEASES_URL = 'https://nodejs.org/dist/index.json';
const IMAGE_VARIANTS = ['', '-alpine', '-slim'];
const repoRoot = path.resolve(__dirname, '..', '..');

function run(command, args) {
    return new Promise(resolve => {
        const child = spawn(command, args);
        let stdout = '';
        let output = '';
        child.stdout.on('data', data => { stdout += data; output += data; });
        child.stderr.on('data', data => { output += data; });
        child.on('close', code => resolve({ code, stdout, output }));
    });
}

async function supportedImages() {
    const releases = await (await fetch(NODE_RELEASES_URL)).json();
    const majorOf = release => Number(release.version.slice(1).split('.')[0]);
    const majors = new Set(releases.filter(release => release.lts).map(majorOf));
    majors.add(majorOf(releases[0]));
    const sortedMajors = [...majors].sort((a, b) => a - b);
    return sortedMajors.flatMap(major => IMAGE_VARIANTS.map(variant => major + variant));
}

async function pullFailure(image, hostPlatform, pull) {
    const inspect = await run('docker', ['manifest', 'inspect', 'node:' + image]);
    if (inspect.code !== 0) return { image, status: 'FAIL', output: pull.output + inspect.output };
    const platforms = JSON.parse(inspect.stdout).manifests.map(entry => entry.platform.os + '/' + entry.platform.architecture);
    if (!platforms.includes(hostPlatform)) return { image, status: 'skipped: no ' + hostPlatform + ' image' };
    return { image, status: 'FAIL', output: pull.output };
}

async function testImage(image, hostPlatform) {
    const pull = await run('docker', ['pull', '-q', 'node:' + image]);
    const cached = (await run('docker', ['image', 'inspect', 'node:' + image])).code === 0;
    if (pull.code !== 0 && !cached) return pullFailure(image, hostPlatform, pull);
    const source = pull.code === 0 ? '' : ' (cached image, registry refused refresh)';
    const build = await run('docker', ['build', '-q', '--pull=false', '--build-arg', 'NODE_IMAGE=' + image, '-f', path.join(__dirname, 'Dockerfile'), repoRoot]);
    if (build.code !== 0) return { image, status: 'FAIL' + source, output: build.output };
    const test = await run('docker', ['run', '--rm', '--init', '-v', repoRoot + ':/deps/app:ro', build.stdout.trim()]);
    return { image, status: (test.code === 0 ? 'pass' : 'FAIL') + source, output: test.output };
}

async function oneAtATime(items, task) {
    const results = [];
    for (const item of items) {
        results.push(await task(item));
    }
    return results;
}

async function main() {
    const requested = process.argv.slice(2);
    const images = requested.length ? requested : await supportedImages();
    const hostPlatform = (await run('docker', ['version', '--format', '{{.Server.Os}}/{{.Server.Arch}}'])).stdout.trim();
    const results = await oneAtATime(images, image => testImage(image, hostPlatform));
    const failures = results.filter(result => result.status.startsWith('FAIL'));
    for (const result of failures) {
        console.log('===== node:' + result.image + ' =====\n' + result.output);
    }
    for (const result of results) {
        console.log('node:' + result.image + ' ' + result.status);
    }
    process.exitCode = failures.length ? 1 : 0;
}

main();
