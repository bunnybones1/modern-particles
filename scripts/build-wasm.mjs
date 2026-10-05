import { execFileSync } from 'node:child_process';
import { copyFileSync } from 'node:fs';
execFileSync('cargo', ['build', '--manifest-path', 'rust/Cargo.toml', '--target', 'wasm32-unknown-unknown', '--release'], { stdio: 'inherit' });
copyFileSync('rust/target/wasm32-unknown-unknown/release/particle_engine.wasm', 'public/engine.wasm');
