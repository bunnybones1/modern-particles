//! Rust initializes a 3D firefly volume and drives the GPU field uniforms.
use std::cell::RefCell;
thread_local! {
    static PARTICLES: RefCell<Vec<f32>> = const { RefCell::new(Vec::new()) };
    static UNIFORMS: RefCell<[f32; 16]> = const { RefCell::new([0.0; 16]) };
}
fn random(state: &mut u32) -> f32 {
    *state ^= *state << 13;
    *state ^= *state >> 17;
    *state ^= *state << 5;
    (*state as f64 / u32::MAX as f64) as f32
}
#[no_mangle]
pub extern "C" fn initialize(count: u32, seed: u32, _aspect: f32) -> *const f32 {
    PARTICLES.with(|p| {
        let mut p = p.borrow_mut();
        p.resize(count as usize * 12, 0.0);
        let mut state = seed.max(1);
        for particle in p.chunks_exact_mut(12) {
            let x = (random(&mut state) * 2.0 - 1.0) * 18.0;
            let y = (random(&mut state) * 2.0 - 1.0) * 11.0;
            let z = (random(&mut state) * 2.0 - 1.0) * 18.0;
            particle.copy_from_slice(&[x,y,z,1.0,0.0,0.0,0.0,0.0,
                random(&mut state),random(&mut state),random(&mut state),random(&mut state)]);
        }
        p.as_ptr()
    })
}
#[no_mangle]
pub extern "C" fn update(time: f32, dt: f32, aspect: f32, speed: f32, turbulence: f32, mouse_x: f32, mouse_y: f32, mouse_active: f32, width: f32, height: f32, palette: f32) -> *const f32 {
    UNIFORMS.with(|u| {
        let mut u = u.borrow_mut();
        *u = [time,dt,aspect,speed,turbulence,mouse_x,mouse_y,mouse_active,
              width,height,palette,40000.0,(time * 0.071).sin(),(time * 0.053).cos(),0.0,0.0];
        u.as_ptr()
    })
}
