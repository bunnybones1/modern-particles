struct Particle { pos: vec4f, velocity: vec4f, traits: vec4f }
struct Params { clock: vec4f, flow: vec4f, display: vec4f, drift: vec4f }
@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(1) var<uniform> params: Params;
@group(0) @binding(2) var<storage, read_write> history: array<vec4f>;
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
 let v = field * (0.17 + params.flow.x * 0.22) + flutter * 0.12;
 let initializeHistory = p.velocity.w < 0.5;
 p.velocity = vec4f(mix(p.velocity.xyz, v, min(1.0, dt * 1.8)),1.0);
 p.pos = vec4f(p.pos.xyz + p.velocity.xyz * dt,1.0);
 let bounds = vec3f(18.0,11.0,18.0);
 let wrapped = any(abs(p.pos.xyz) > bounds);
 p.pos = vec4f((fract((p.pos.xyz + bounds) / (bounds * 2.0))) * bounds * 2.0 - bounds,1.0);
 // Keep actual world-space positions in a per-particle ring buffer.
 // Clear history on initialization and wrapping to avoid a trail across the volume.
 let base = id.x * 33u;
 if (initializeHistory || wrapped) {
   for (var sample = 0u; sample < 33u; sample++) { history[base + sample] = p.pos; }
 } else if (params.display.w > 0.5) {
   history[base + u32(params.drift.z)] = p.pos;
 }
 particles[id.x] = p;
}
