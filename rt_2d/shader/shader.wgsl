struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) tex_coords: vec2<f32>,
};

struct CameraUniform {
    resolution: vec2<f32>,
    centre: vec2<f32>,
    zoom: f32
}

@group(0) @binding(0) var<uniform> camera: CameraUniform;

@group(1) @binding(0) var density: texture_storage_2d<r32uint, read>;
@group(1) @binding(1) var emission: texture_storage_2d<r32float, read>;

@vertex
fn vs_main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var result: VertexOutput;
    let x = i32(vertex_index) / 2;
    let y = i32(vertex_index) & 1;
    let tc = vec2<f32>(
        f32(x) * 2.0,
        f32(y) * 2.0
    );
    result.position = vec4<f32>(
        tc.x * 2.0 - 1.0,
        1.0 - tc.y * 2.0,
        0.0, 1.0
    );
    result.tex_coords = tc;
    return result;
}

struct HitResult {
    cell: vec2i,
    hit: bool
}

const MAX_RAY_LENGTH = 10.;

fn cast_ray(pos: vec2f, dir: vec2f) -> HitResult {
    let dydx = dir.y / dir.x;
    let dxdy = dir.x / dir.y;

    var result: HitResult;
    let ray_step_size = vec2f(sqrt(1. + dydx*dydx), sqrt(1. + dxdy*dxdy));
    var current_cell = vec2i(pos);
    var step: vec2i;
    var ray_length: vec2f;


    if dir.x < 0. {
        step.x = -1;
        ray_length.x = fract(pos.x) * ray_step_size.x;
    } else {
        step.x = 1;
        ray_length.x = (1. - fract(pos.x)) * ray_step_size.x;
    }

    if dir.y < 0. {
        step.y = -1;
        ray_length.y = fract(pos.y) * ray_step_size.y;
    } else {
        step.y = 1;
        ray_length.y = (1. - fract(pos.y)) * ray_step_size.y;
    }

    var distance = 0.;
    while (distance < MAX_RAY_LENGTH) {
        if ray_length.x < ray_length.y {
            current_cell.x += step.x;
            distance = ray_length.x;
            ray_length.x += ray_step_size.x;
        } else {
            current_cell.y += step.y;
            distance = ray_length.y;
            ray_length.y += ray_step_size.y;
        }

        let cell = textureLoad(density, current_cell).r;

        if cell == 1u {
            result.cell = current_cell;
            result.hit = true;
            return result;
        }
    }

    result.hit = false;
    return result;
}

// https://marc-b-reynolds.github.io/math/2016/03/29/weyl_hash.html
const W0 = 0.5545497;
const W1 = 0.308517;

// fn hash(c: vec2f) -> f32 {
//   let x = c.x*fract(c.x * W0);
//   let y = c.y*fract(c.y * W1);
//   return fract(x*y);
// }

// https://www.shadertoy.com/view/XlGcRh
// UE4's RandFast function
fn hash(u: vec2f) -> f32 {
    var v = u;
    v = (1./4320.) * v + vec2(0.25,0.);
    let state = fract( dot( v * v, vec2f(3571.)));
    return fract( state * state * (3571. * 2.));
}

fn random_unit(pos: vec2f) -> vec2f {
    var v = vec2f(
        hash(pos + vec2f(0.1, 0.3)),
        hash(pos + vec2f(0.7, 0.9))
    ) - 0.5;

    var l = dot(v, v);
    for (var i = 0; i < 50 && (l > 1. || l < 0.0000001); i++) {
        v = vec2f(
            hash(pos + vec2f(f32(i) * 5.1, 0.3)),
            hash(pos + vec2f(0.7, f32(i) * 6.3)),
        ) - 0.5;
        l = dot(v, v);
    }

    return normalize(v);
}

const SAMPLE_COUNT = 500;

fn sample(world_pos: vec2f, screen_pos: vec2f) -> vec3f {
    var cumulative = vec3f(0., 0., 0.);

    for (var i = 0; i < SAMPLE_COUNT; i++) {
        let dir = random_unit(screen_pos * 500. + f32(i) * 20.);
        let ray = cast_ray(world_pos, dir);
        if (ray.hit) {
            cumulative += vec3f(textureLoad(emission, ray.cell).r);
        }
    }

    return cumulative / f32(SAMPLE_COUNT);
}

@fragment
fn fs_main(vertex: VertexOutput) -> @location(0) vec4<f32> {
    let world_pos = (vertex.tex_coords * camera.resolution - camera.resolution / 2.) * camera.zoom + camera.centre;

    let cell = world_pos / 50.;

    let solid = textureLoad(density, vec2i(world_pos)).r == 1u;

    if (!solid) {
        let ret = sample(world_pos, vertex.tex_coords);
        return vec4f(ret, 1.0);
        // let r = hash(vertex.tex_coords * 500.);
        // return vec4f(r, r, r, 1.0);
        // return vec4f(random_unit(pos), 0.0, 1.0);
    }
    

    let col = max(textureLoad(emission, vec2i(world_pos)).r * f32(solid), 0.01);

    return vec4f(col, col, col, 1.);
}

