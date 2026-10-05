# FIREFLIES

[Live demo](https://modern-particles.pages.dev/) · [Source](https://github.com/bunnybones1/modern-particles)

![Fireflies motion-history field](fireflies-preview.jpg)

40,000 fireflies in a fullscreen, interactive 3D field. Built with Vite, a dependency-free Rust WASM engine, and WebGPU compute/render pipelines.

## Run locally

Requires Node.js 20.19+ or 22.12+, Rust, and the `wasm32-unknown-unknown` target:

```sh
rustup target add wasm32-unknown-unknown
npm install
npm run wasm
npm run dev
```

Open http://localhost:5173 in a browser with WebGPU and hardware acceleration enabled.

## Controls

Move the pointer to shift the camera. Tune adjusts speed, turbulence, and palette. Space pauses, R reseeds, H hides the interface. The upper-right button enters fullscreen.

## Architecture

Rust initializes 40,000 3D particle records with position, velocity, and individual flicker/size/color seeds. It produces a 64-byte uniform block each frame. A WebGPU compute shader updates gentle 3D drift. The renderer projects world-space light billboards with perspective, depth attenuation, individual pulses, and pointer-driven camera parallax.

Every frame clears the canvas. There is no trail texture, temporal accumulation, or motion blur. Compact halos surround crisp light cores, with tapered ribbons connecting sixteen seconds of recorded world-space motion, at 50% tail opacity. A GPU ring buffer stores 33 positions per firefly at half-second simulation intervals. Ribbon vertices interpolate between the recorded positions; history resets on reseed or boundary wrapping. Particle state stays on the GPU, with only uniforms uploaded each frame. Canvas pixel ratio is capped at two.

## Production and Cloudflare

```sh
npm run build
npm run preview
npm run deploy
```

`npm run deploy` builds Rust/WASM and Vite, then uploads `dist` to Cloudflare Pages. The deploy script selects the Cloudflare account; authenticate with `npx wrangler login` if needed.
