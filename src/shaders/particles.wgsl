struct Particle { pos: vec4f, velocity: vec4f, traits: vec4f }
struct Params { clock: vec4f, flow: vec4f, display: vec4f, drift: vec4f, camera: vec4f }
@group(0) @binding(0) var<storage, read> particles: array<Particle>;
@group(0) @binding(1) var<uniform> params: Params;
@group(0) @binding(2) var<storage, read> history: array<vec4f>;
struct Output { @builtin(position) position: vec4f, @location(0) uv: vec2f, @location(1) color: vec3f, @location(2) brightness: f32, @location(3) isTail: f32 }
fn project(world: vec3f) -> vec3f {
 let x = world.x * params.camera.x + world.z * params.camera.y;
 let z = -world.x * params.camera.y + world.z * params.camera.x;
 let y = world.y * params.camera.z - z * params.camera.w;
 let depth = max(1.0,26.0 - (world.y * params.camera.w + z * params.camera.z));
 return vec3f(vec2f(x,y) / (depth * 0.58),depth);
}
fn pathPoint(instance: u32, point: u32) -> vec3f {
 if (point == 0u) { return particles[instance].pos.xyz; }
 let cursor = u32(params.drift.z);
 let base = instance * 33u;
 // Each segment spans a quarter of a second; interpolate samples as the clock advances.
 let older = (cursor + 33u - point * 2u) % 33u;
 let newer = (older + 1u) % 33u;
 return mix(history[base + older].xyz,history[base + newer].xyz,params.drift.w);
}
fn hueToRgb(hue: f32) -> vec3f {
 let rgb = clamp(abs(fract(vec3f(hue) + vec3f(0.0,2.0/3.0,1.0/3.0)) * 6.0 - 3.0) - 1.0,vec3f(0.0),vec3f(1.0));
 return mix(vec3f(1.0),rgb,0.7);
}
@vertex fn vertex(@builtin(vertex_index) vertex: u32, @builtin(instance_index) instance: u32) -> Output {
 let p = particles[instance];
 let corners = array<vec2f,4>(vec2f(-1,-1),vec2f(1,-1),vec2f(-1,1),vec2f(1,1));
 var corner = vec2f(0.0,select(-1.0,1.0,vertex % 2u == 1u));
 if (vertex < 4u) { corner = corners[vertex]; }
 let head = project(p.pos.xyz);
 let depth = head.z;
 var center = head.xy;
 var normal = vec2f(0.0,1.0);
 var radius = max((0.045 + p.traits.y * 0.04) / (depth * 0.58),4.0 / params.display.y);
 var offset = corner * radius;
 var out: Output;
 out.uv = corner;
 out.isTail = 0.0;
 if (vertex >= 4u) {
   let point = (vertex - 4u) / 2u;
   let u = f32(point) / 16.0;
   let position = project(pathPoint(instance,point));
   let before = project(pathPoint(instance,select(0u,point-1u,point>0u)));
   let after = project(pathPoint(instance,min(16u,point+1u)));
   let tangent = normalize(after.xy - before.xy + vec2f(0.000001,0.0));
   normal = vec2f(-tangent.y,tangent.x);
   radius = max((0.045 + p.traits.y * 0.04) / (position.z * 0.58),4.0 / params.display.y);
   let width = 0.48 * pow(max(0.0,1.0-u),0.85);
   center = position.xy;
   offset = normal * corner.y * radius * width;
   out.uv = vec2f(u,corner.y);
   out.isTail = 1.0;
 }
 out.position = vec4f((center + offset) * vec2f(1.0 / params.clock.z,1.0),0.5,1.0);
 var color = hueToRgb(p.traits.z);
 if (params.display.z > 0.5 && params.display.z < 1.5) { color = mix(vec3f(1.0,0.19,0.03),vec3f(1.0,0.72,0.22),p.traits.z); }
 if (params.display.z > 1.5) { color = mix(vec3f(0.19,0.4,1.0),vec3f(0.65,0.83,1.0),p.traits.z); }
 out.color = color;
 // Flicker is evaluated once per particle by the compute pass.
 out.brightness = p.pos.w * mix(0.32,1.0,clamp(1.0 - depth / 52.0,0.0,1.0));
 return out;
}
@fragment fn fragment(in: Output) -> @location(0) vec4f {
 if (in.isTail > 0.5) {
   let progress = max(0.0,1.0 - in.uv.x);
   let edge = 1.0 - smoothstep(0.35,1.0,abs(in.uv.y));
   let headJoin = smoothstep(0.0,0.15,in.uv.x * 60.0);
   // Premultiplied emission: half the previous tail opacity, preserving the head.
   let opacity = 0.5 * edge * pow(progress,0.85) * headJoin;
   if (opacity < 0.001) { discard; }
   return vec4f(in.color * 1.1 * in.brightness * opacity,opacity);
 }
 let r = length(in.uv);
 let core = 1.0 - smoothstep(0.08,0.28,r);
 let halo = exp(-r * r * 6.0) * (1.0 - smoothstep(0.75,1.0,r));
 if (halo + core < 0.001) { discard; }
 let color = (in.color * halo * 0.45
              + mix(in.color,vec3f(1.0),0.6) * core) * in.brightness;
 return vec4f(color,1.0);
}
