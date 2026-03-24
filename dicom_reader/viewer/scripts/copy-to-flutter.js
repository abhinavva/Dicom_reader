/**
 * Copy Vite dist output to Flutter assets so the app serves the bundled viewer.
 * Run after: npm run build
 * Usage: node scripts/copy-to-flutter.js
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const distDir = path.join(__dirname, '..', 'dist');
const targetDir = path.join(__dirname, '..', '..', 'assets', 'cornerstone_viewer');

if (!fs.existsSync(distDir)) {
  console.error('Dist folder not found. Run "npm run build" first.');
  process.exit(1);
}

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
    for (const name of fs.readdirSync(src)) {
      copyRecursive(path.join(src, name), path.join(dest, name));
    }
  } else {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
  }
}

copyRecursive(distDir, targetDir);
console.log('Copied viewer dist to', targetDir);
