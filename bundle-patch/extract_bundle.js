const { readFilesystemSync, readFileSync } = require('@electron/asar/lib/disk');
const fs = require('fs');
const path = require('path');

const archive = 'C:/Users/<user>/AppData/Local/Programs/@opencode-aidesktop/resources/app.asar';
const target = 'out/renderer/assets/main-Cpm5Nopr.js';
const outFile = path.join(__dirname, 'main-Cpm5Nopr.orig.js');

const filesystem = readFilesystemSync(archive);
const header = filesystem.getHeader();

console.log('Header algorithm:', header.algorithm);
console.log('Header blockSize:', header.blockSize);

// Navigate to the file entry
let entry = header.files;
for (const part of target.split('/')) {
    entry = entry[part];
}
console.log('Entry offset:', entry.offset, 'size:', entry.size);
if (entry.integrity) {
    console.log('Integrity:', JSON.stringify(entry.integrity, null, 2));
}

const buf = readFileSync(filesystem, target, entry);
console.log('Extracted size:', buf.length);
fs.writeFileSync(outFile, buf);
console.log('Written to:', outFile);