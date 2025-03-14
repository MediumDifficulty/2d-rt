struct CameraUniform {
    resolution: vec2<f32>,
    centre: vec2<f32>,
    zoom: f32,
    entropy: f32,
    moved: u32,
}

@group(0) @binding(0) var surface_texture_in: texture_storage_2d<rgba32float, read>;
@group(0) @binding(1) var surface_texture_out: texture_storage_2d<rgba32float, write>;

@group(0) @binding(2) var sample_count_in: texture_storage_2d<r32uint, read>;
@group(0) @binding(3) var sample_count_out: texture_storage_2d<r32uint, write>;

@group(1) @binding(0) var density: texture_storage_2d<r32uint, read>;
@group(1) @binding(1) var emission: texture_storage_2d<r32float, read>;
@group(1) @binding(2) var colour: texture_storage_2d<rgba32float, read>;

@group(2) @binding(0) var<uniform> camera: CameraUniform;

struct HitResult {
    hit: bool,
    cell: vec2i,
    pos: vec2f,
    normal: vec2i    
}

const MAX_RAY_LENGTH = 50.;

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
            result.normal = vec2i(-step.x, 0);
        } else {
            current_cell.y += step.y;
            distance = ray_length.y;
            ray_length.y += ray_step_size.y;
            result.normal = vec2i(0, -step.y);
        }

        let cell = textureLoad(density, current_cell).r;

        if cell == 1u {
            result.cell = current_cell;
            result.hit = true;
            result.pos = pos + distance * dir;
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
    var v = u + camera.entropy;
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
            hash(v * 100. + vec2f(f32(i) * 5.1, 0.3)),
            hash(v * 100. + vec2f(0.7, f32(i) * 6.3)),
        ) - 0.5;
        l = dot(v, v);
    }

    return normalize(v);
}

fn random_semi(pos: vec2f, normal: vec2i) -> vec2f {
    let rand = random_unit(pos);

    if (normal.x != 0) {
        return vec2f(
            abs(rand.x) * f32(normal.x),
            rand.y
        );
    } else {
        return vec2f(
            rand.x,
            abs(rand.y) * f32(normal.y)
        );
    }
}

const BOUNCES = 5;

fn send_ray(world_pos: vec2f, world_dir: vec2f) -> vec3f {
    var pos = world_pos;
    var dir = world_dir;
    var transmission = 1.;
    var col = vec3f(0.);

    for (var i = 0; i < BOUNCES; i++) {
        let ray = cast_ray(pos, dir);

        if (!ray.hit) {
            return col;
        }

        pos = ray.pos;

        col += transmission * textureLoad(emission, ray.cell).r * textureLoad(colour, ray.cell).rgb;

        transmission *= 0.6;

        dir = random_semi(dir, ray.normal);
    }

    return col;
}

const SAMPLE_COUNT = 50;

fn sample(world_pos: vec2f, screen_pos: vec2u) -> vec3f {
    var cumulative = vec3f(0., 0., 0.);

    var dir = random_unit(vec2f(screen_pos));
    for (var i = 0; i < SAMPLE_COUNT; i++) {
        let dir = random_unit(dir + f32(i) * vec2f(2.0, 7.0));
        let col = send_ray(world_pos, dir);
    
        cumulative += col;
    }

    return cumulative / f32(SAMPLE_COUNT);
}

const MIN_BRIGHTNESS = 0.01;

@compute @workgroup_size(8, 8, 1)
fn sample_kernel(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let world_pos = (vec2f(global_id.xy) - camera.resolution / 2.) * camera.zoom + camera.centre;

    let solid = textureLoad(density, vec2i(world_pos)).r == 1u;

    var col: vec3f;
    if (!solid) {
        let ret = sample(world_pos, global_id.xy);
        col = ret;
    } else {
        let base_col = textureLoad(colour, vec2i(world_pos)).rgb;
        let emission = textureLoad(emission, vec2i(world_pos)).r;

        col = vec3f(base_col * max(emission, MIN_BRIGHTNESS));
    }
    
    var new_count: u32;
    var new_col: vec3f;

    if camera.moved == 1u {
        new_count = 1u;
        new_col = col;
    } else {
        let current_col = textureLoad(surface_texture_in, vec2i(global_id.xy)).rgb;
        new_count = textureLoad(sample_count_in, vec2i(global_id.xy)).r + 1u;
        new_col = current_col + (col - current_col) / f32(new_count);
    }
     

    textureStore(surface_texture_out, vec2i(global_id.xy), vec4f(new_col, 1.0));
    textureStore(sample_count_out, vec2i(global_id.xy), vec4u(new_count, 0u, 0u, 0u));
}