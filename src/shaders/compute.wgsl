struct Particle { pos: vec4f, velocity: vec4f, traits: vec4f }
struct Params { clock: vec4f, flow: vec4f, display: vec4f, drift: vec4f, camera: vec4f }
@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(1) var<uniform> params: Params;
@group(0) @binding(2) var<storage, read_write> history: array<vec4f>;
// Integer hashing makes each lattice hue repeatable, with no per-frame randomness.
fn latticeHue(cell: vec3i) -> f32 {
 let q = bitcast<vec3u>(cell);
 var h = (q.x * 1597334677u) ^ (q.y * 3812015801u) ^ (q.z * 2798796415u);
 h = (h ^ (h >> 16u)) * 2246822519u;
 h = (h ^ (h >> 13u)) * 3266489917u;
 h = h ^ (h >> 16u);
 return f32(h & 16777215u) / 16777216.0;
}
fn hueField(position: vec3f) -> f32 {
 // A cell spans 12.5 world units: broad, slowly changing regions of color.
 let q = position * 0.08;
 let cell = vec3i(floor(q));
 let f = fract(q);
 let blend = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
 let bottom = mix(
   mix(latticeHue(cell),latticeHue(cell + vec3i(1,0,0)),blend.x),
   mix(latticeHue(cell + vec3i(0,1,0)),latticeHue(cell + vec3i(1,1,0)),blend.x),blend.y);
 let top = mix(
   mix(latticeHue(cell + vec3i(0,0,1)),latticeHue(cell + vec3i(1,0,1)),blend.x),
   mix(latticeHue(cell + vec3i(0,1,1)),latticeHue(cell + vec3i(1,1,1)),blend.x),blend.y);
 return mix(bottom,top,blend.z);
}
@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) id: vec3u) {
 if (id.x >= 40000u) { return; }
 var p = particles[id.x];
 let t = params.clock.x;
 let dt = params.clock.y * params.clock.w;
 let q = p.pos.xyz * 0.28;
 let phase = p.traits.x * 6.28318;
 let field = vec3f(sin(q.y + t * 0.17) + cos(q.z * 1.3 - t * 0.11),
                  sin(q.z + t * 0.13) + cos(q.x * 1.1 + t * 0.09),
                  sin(q.x + t * 0.12) - cos(q.y * 1.2 - t * 0.15));
 let flutter = vec3f(sin(t * 1.2 + phase),cos(t * 0.8 + phase * 2.0),sin(t * 0.9 + phase * 3.0));
 var v = field * (0.17 + params.flow.x * 0.22) + flutter * 0.12;
 // Stir around the pointer's ray, using the same camera transform as rendering.
 // The radius scales with depth, keeping the interaction under the visible cursor.
 if (params.flow.w > 0.0) {
   let cameraX = p.pos.x * params.camera.x + p.pos.z * params.camera.y;
   let rotatedZ = -p.pos.x * params.camera.y + p.pos.z * params.camera.x;
   let cameraY = p.pos.y * params.camera.z - rotatedZ * params.camera.w;
   let cameraZ = p.pos.y * params.camera.w + rotatedZ * params.camera.z;
   let depth = max(1.0,26.0 - cameraZ);
   let delta = vec2f(cameraX,cameraY) - params.flow.yz * depth * 0.58;
   let radius = max(0.75,depth * 0.58 * 0.16);
   let local = delta / radius;
   let influence = exp(-dot(local,local) * 1.5) * params.flow.w;
   let swirl = vec2f(-local.y,local.x) * 5.0;
   let push = local * 0.8;
   let cameraForce = vec3f(swirl + push,0.35 * sin(phase + t)) * influence;
   // Inverse pitch and yaw map the force back into simulation world space.
   let forceY = cameraForce.y * params.camera.z + cameraForce.z * params.camera.w;
   let forceZ = -cameraForce.y * params.camera.w + cameraForce.z * params.camera.z;
   v += vec3f(cameraForce.x * params.camera.x - forceZ * params.camera.y,forceY,
              cameraForce.x * params.camera.y + forceZ * params.camera.x);
 }
 // Steer gently inward near the front/back faces instead of teleporting in depth.
 let depthTurn = smoothstep(16.0,18.0,abs(p.pos.z));
 v.z = mix(v.z,-sign(p.pos.z) * max(abs(v.z),0.25),depthTurn);
 let initializeHistory = p.velocity.w < 0.5;
 p.velocity = vec4f(mix(p.velocity.xyz, v, min(1.0, dt * 1.8)),1.0);
 p.pos = vec4f(p.pos.xyz + p.velocity.xyz * dt,1.0);
 let bounds = vec3f(18.0,11.0,18.0);
 let wrapped = any(abs(p.pos.xy) > bounds.xy);
 let wrappedXY = fract((p.pos.xy + bounds.xy) / (bounds.xy * 2.0)) * bounds.xy * 2.0 - bounds.xy;
 p.pos = vec4f(wrappedXY,p.pos.z,1.0);
 // Reflect any residual overshoot, preserving the depth trajectory and its history.
 if (abs(p.pos.z) > bounds.z) {
   p.pos.z = sign(p.pos.z) * (2.0 * bounds.z - abs(p.pos.z));
   p.velocity.z = -p.velocity.z;
 }
 // Keep actual world-space positions in a per-particle ring buffer.
 // Clear history on initialization and wrapping to avoid a trail across the volume.
 let base = id.x * 33u;
 if (initializeHistory || wrapped) {
   for (var sample = 0u; sample < 33u; sample++) { history[base + sample] = p.pos; }
 } else if (params.display.w > 0.5) {
   history[base + u32(params.drift.z)] = p.pos;
 }
 p.traits.z = hueField(p.pos.xyz);
 let pulse = pow(0.5 + 0.5 * sin(t * (0.7 + p.traits.w * 1.2) + p.traits.x * 6.28318),5.0);
 p.pos.w = 0.10 + pulse * 1.5;
 particles[id.x] = p;
}
