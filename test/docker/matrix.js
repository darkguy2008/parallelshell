#!/usr/bin/env node
'use strict';
const { spawn } = require('child_process');
const path = require('path');
const { nodeReleases, supportedMajors } = require('../support/node-lines');

const IMAGE_VARIANTS = ['', '-alpine', '-slim'];
const LINUX_RELEASE_FILE = 'linux-x64';
const SUITE_TIMEOUT_MS = 10 * 60 * 1000;
const repoRoot = path.resolve(__dirname, '..', '..');

function run(command, args, options) {
    return new Promise(resolve => {
        const child = spawn(command, args, options);
        let stdout = '';
        let output = '';
        child.stdout.on('data', data => { stdout += data; output += data; });
        child.stderr.on('data', data => { output += data; });
        child.on('close', code => resolve({ code, stdout, output }));
    });
}

async function supportedTags() {
    return supportedMajors(await nodeReleases(), LINUX_RELEASE_FILE).flatMap(major => IMAGE_VARIANTS.map(variant => major + variant));
}

async function unavailable(image, hostPlatform, pull) {
    const inspect = await run('docker', ['manifest', 'inspect', image]);
    if (inspect.code !== 0) return { image, failed: true, status: 'FAIL', output: pull.output + inspect.output };
    const platforms = JSON.parse(inspect.stdout).manifests.map(entry => entry.platform.os + '/' + entry.platform.architecture);
    if (platforms.includes(hostPlatform)) return { image, failed: true, status: 'FAIL', output: pull.output };
    return { image, failed: false, status: 'skipped: no ' + hostPlatform + ' image' };
}

async function build(tag, hostPlatform) {
    const image = 'node:' + tag;
    const pull = await run('docker', ['pull', '-q', image]);
    const cached = pull.code === 0 || (await run('docker', ['image', 'inspect', image])).code === 0;
    if (!cached) return unavailable(image, hostPlatform, pull);
    const note = pull.code === 0 ? '' : ' (cached image, registry refused refresh)';
    const built = await run('docker', ['build', '-q', '--pull=false', '--build-arg', 'NODE_IMAGE=' + tag, '-f', path.join(__dirname, 'Dockerfile'), repoRoot]);
    if (built.code !== 0) return { image, failed: true, status: 'FAIL' + note, output: built.output };
    return { image, note, testImage: built.stdout.trim() };
}

async function runTests(prepared) {
    if (!prepared.testImage) return prepared;
    const tests = await run('docker', ['run', '--rm', '--init', '-v', repoRoot + ':/deps/app:ro', prepared.testImage], { timeout: SUITE_TIMEOUT_MS });
    const failed = tests.code !== 0;
    return { image: prepared.image, failed, status: (failed ? 'FAIL' : 'pass') + prepared.note, output: tests.output };
}

async function main() {
    const requested = process.argv.slice(2);
    const tags = requested.length ? requested : await supportedTags();
    const hostPlatform = (await run('docker', ['version', '--format', '{{.Server.Os}}/{{.Server.Arch}}'])).stdout.trim();
    const prepared = await Promise.all(tags.map(tag => build(tag, hostPlatform)));
    const results = await Promise.all(prepared.map(runTests));
    const failures = results.filter(result => result.failed);
    for (const result of failures) {
        console.log('===== ' + result.image + ' =====\n' + result.output);
    }
    for (const result of results) {
        console.log(result.image + ' ' + result.status);
    }
    if (failures.length) process.exitCode = 1;
}

main();
