import './style.css';
import computeCode from './shaders/compute.wgsl?raw';
import particleCode from './shaders/particles.wgsl?raw';

const COUNT = 40_000;
const TAIL_SEGMENTS = 16;
const HISTORY_INTERVAL = 0.125; // 33 samples span four simulation seconds.
const $ = (id) => document.getElementById(id);
let paused = false, reseed = false, simulationTime = 0, pointer = [0, 0, 0];
$('pause').onclick = () => { paused = !paused; $('pause').innerHTML = paused ? 'Resume <span>▷</span>' : 'Pause <span>Ⅱ</span>'; $('pause').setAttribute('aria-label', paused ? 'Resume simulation' : 'Pause simulation'); };
$('reset').onclick = () => { reseed = true; };
$('settings').onclick = () => { $('panel').hidden = !$('panel').hidden; $('settings').setAttribute('aria-expanded', String(!$('panel').hidden)); };
$('fullscreen').onclick = async () => { try { if (document.fullscreenElement) await document.exitFullscreen(); else await document.documentElement.requestFullscreen(); } catch (error) { console.warn(error); } };
for (const id of ['speed', 'turbulence']) $(id).oninput = () => { $(id + '-value').value = Number($(id).value).toFixed(1) + (id === 'speed' ? '×' : ''); };
window.addEventListener('keydown', (event) => {
 if (['INPUT', 'SELECT', 'BUTTON'].includes(event.target.tagName)) return;
 if (event.code === 'Space') { event.preventDefault(); $('pause').click(); }
 if (event.key.toLowerCase() === 'r') reseed = true;
 if (event.key.toLowerCase() === 'h') document.body.classList.toggle('ui-hidden');
});
window.addEventListener('pointermove', (event) => { pointer = [(event.clientX / innerWidth * 2 - 1) * innerWidth / innerHeight, 1 - event.clientY / innerHeight * 2, event.target === $('canvas') ? 1 : 0]; });
window.addEventListener('pointerup', (event) => { if (event.pointerType === 'touch') pointer[2] = 0; });
document.addEventListener('pointerleave', () => { pointer[2] = 0; });
window.addEventListener('blur', () => { pointer[2] = 0; });
function fail(message) { $('error-message').textContent = message; $('error').hidden = false; $('status').textContent = 'GPU UNAVAILABLE'; }
async function start() {
 if (!navigator.gpu) throw new Error('WebGPU is unavailable in this browser. Open this page in a current Chrome, Edge, or Safari browser with hardware acceleration enabled.');
 const adapter = await navigator.gpu.requestAdapter({ powerPreference: 'high-performance' });
 if (!adapter) throw new Error('No WebGPU adapter was found. Enable hardware acceleration and try again.');
 const device = await adapter.requestDevice();
 device.lost.then((info) => fail(`The GPU connection was lost: ${info.message}. Reload to reconnect.`));
 device.addEventListener('uncapturederror', (event) => { console.error(event.error); fail(event.error.message); });
 const response = await fetch('/engine.wasm');
 if (!response.ok) throw new Error('The Rust engine could not be loaded.');
 const { instance } = await WebAssembly.instantiateStreaming(response, {});
 const engine = instance.exports;
 const canvas = $('canvas'), context = canvas.getContext('webgpu');
 const format = navigator.gpu.getPreferredCanvasFormat();
 const particleBuffer = device.createBuffer({ size: COUNT * 48, usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST });
 const historyBuffer = device.createBuffer({ size: COUNT * 33 * 16, usage: GPUBufferUsage.STORAGE });
 const uniformData = new Float32Array(20);
 const uniformBuffer = device.createBuffer({ size: 80, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
 const modules = [computeCode, particleCode].map(code => device.createShaderModule({ code }));
 for (const module of modules) { const info = await module.getCompilationInfo(); const errors = info.messages.filter(m => m.type === 'error'); if (errors.length) throw new Error(errors.map(m => `${m.lineNum}: ${m.message}`).join('\n')); }
 const compute = await device.createComputePipelineAsync({ layout: 'auto', compute: { module: modules[0], entryPoint: 'main' } });
 const render = await device.createRenderPipelineAsync({ layout: 'auto', vertex: { module: modules[1], entryPoint: 'vertex' }, fragment: { module: modules[1], entryPoint: 'fragment', targets: [{ format, blend: { color: { srcFactor: 'one', dstFactor: 'one', operation: 'add' }, alpha: { srcFactor: 'one', dstFactor: 'one', operation: 'add' } } }] }, primitive: { topology: 'triangle-list' } });
 const particleGroup = (pipeline) => device.createBindGroup({ layout: pipeline.getBindGroupLayout(0), entries: [{ binding: 0, resource: { buffer: particleBuffer } }, { binding: 1, resource: { buffer: uniformBuffer } }, { binding: 2, resource: { buffer: historyBuffer } }] });
 const computeGroup = particleGroup(compute), renderGroup = particleGroup(render);
 // Four head vertices + two shared vertices at each of seventeen ribbon points.
 const indices = new Uint16Array(6 + TAIL_SEGMENTS * 6);
 indices.set([0,1,2,2,1,3]);
 for (let segment = 0; segment < TAIL_SEGMENTS; segment++) {
  const base = 4 + segment * 2;
  indices.set([base,base+2,base+1,base+1,base+2,base+3],6 + segment * 6);
 }
 const indexBuffer = device.createBuffer({ size: indices.byteLength, usage: GPUBufferUsage.INDEX | GPUBufferUsage.COPY_DST });
 device.queue.writeBuffer(indexBuffer,0,indices);
 let sized = false, historyCursor = 0, historyElapsed = 0;
 function seed() { historyCursor = 0; historyElapsed = 0; const ptr = engine.initialize(COUNT, crypto.getRandomValues(new Uint32Array(1))[0], canvas.width / canvas.height); device.queue.writeBuffer(particleBuffer, 0, new Float32Array(engine.memory.buffer, ptr, COUNT * 12)); }
 function resize() {
  const ratio = Math.min(devicePixelRatio, 2);
  const width = Math.min(device.limits.maxTextureDimension2D, Math.max(1, Math.round(innerWidth * ratio)));
  const height = Math.min(device.limits.maxTextureDimension2D, Math.max(1, Math.round(innerHeight * ratio)));
  if (canvas.width === width && canvas.height === height && sized) return;
  canvas.width = width; canvas.height = height;
  context.configure({ device, format, alphaMode: 'opaque' });
  sized = true;
  seed();
 }
 resize();
 $('status').textContent = '40,000 / MOTION HISTORY';
 window.flowDiagnostics = { count: COUNT, backend: 'WebGPU', engine: 'Rust / WASM', ready: true, verticesPerParticle: 38, indicesPerParticle: indices.length };
 let last = performance.now(), fpsTime = last, frames = 0;
 function frame(now) {
  if (!$('error').hidden) return;
  resize();
  const dt = Math.min((now - last) / 1000, 0.035); last = now;
  if (reseed) { seed(); reseed = false; }
  if (!paused && !document.hidden) {
   simulationTime += dt * Number($('speed').value);
   const ptr = engine.update(simulationTime, dt, canvas.width / canvas.height, Number($('speed').value), Number($('turbulence').value), ...pointer, canvas.width, canvas.height, Number($('palette').value));
   historyElapsed += dt * Number($('speed').value);
   let writeHistory = 0;
   if (historyElapsed >= HISTORY_INTERVAL) {
    historyElapsed -= HISTORY_INTERVAL;
    historyCursor = (historyCursor + 1) % 33;
    writeHistory = 1;
   }
   uniformData.set(new Float32Array(engine.memory.buffer,ptr,16));
   const uniforms = uniformData;
   const yaw = pointer[0] * 0.065 + Math.sin(simulationTime * 0.027) * 0.08;
   const pitch = pointer[1] * 0.06;
   uniforms[16] = Math.cos(yaw); uniforms[17] = Math.sin(yaw);
   uniforms[18] = Math.cos(pitch); uniforms[19] = Math.sin(pitch);
   uniforms[11] = writeHistory;
   uniforms[14] = historyCursor;
   uniforms[15] = historyElapsed / HISTORY_INTERVAL;
   device.queue.writeBuffer(uniformBuffer, 0, uniforms);
   const encoder = device.createCommandEncoder();
   const simulation = encoder.beginComputePass(); simulation.setPipeline(compute); simulation.setBindGroup(0, computeGroup); simulation.dispatchWorkgroups(Math.ceil(COUNT / 256)); simulation.end();
   const screen = encoder.beginRenderPass({ colorAttachments: [{ view: context.getCurrentTexture().createView(), loadOp: 'clear', storeOp: 'store', clearValue: [0.003,0.008,0.006,1] }] });
   screen.setPipeline(render); screen.setBindGroup(0, renderGroup); screen.setIndexBuffer(indexBuffer,'uint16'); screen.drawIndexed(indices.length, COUNT); screen.end();
   device.queue.submit([encoder.finish()]);
  }
  frames++;
  if (now - fpsTime >= 700) { const fps = Math.round(frames * 1000 / (now - fpsTime)); $('fps').textContent = paused ? 'PAUSED' : `${fps} FPS`; window.flowDiagnostics.fps = fps; frames = 0; fpsTime = now; }
  requestAnimationFrame(frame);
 }
 requestAnimationFrame(frame);
}
start().catch(error => { console.error(error); fail(error.message); });
