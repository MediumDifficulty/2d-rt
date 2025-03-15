package rt_2d

import "vendor:wgpu"
import "core:math/linalg"
import "core:math/rand"
import "core:math"

WORLD_SIZE :: [2]u32{128, 128}
WORLD_CELLS :: WORLD_SIZE[0] * WORLD_SIZE[1]

world: PixelWorld

world_init :: proc() {
    create_texture :: proc(format: wgpu.TextureFormat) -> wgpu.Texture {
        return wgpu.DeviceCreateTexture(wgpu_state.device, &wgpu.TextureDescriptor{
            size = wgpu.Extent3D{
                width = WORLD_SIZE[0],
                height = WORLD_SIZE[1],
                depthOrArrayLayers = 1
            },
            mipLevelCount = 1,
            sampleCount = 1,
    
            dimension = ._2D,
            format = format,
            usage = { .StorageBinding, .CopyDst }
        })
    }

    world.density = create_texture(wgpu.TextureFormat.R32Uint)
    world.emission = create_texture(wgpu.TextureFormat.R32Float)
    world.colour = create_texture(wgpu.TextureFormat.RGBA32Float)

    world.layout = wgpu.DeviceCreateBindGroupLayout(wgpu_state.device, &wgpu.BindGroupLayoutDescriptor{
        entryCount = 3,
        entries = raw_data([]wgpu.BindGroupLayoutEntry{
            wgpu.BindGroupLayoutEntry {
                binding = 0,
                visibility = { .Compute },
                storageTexture = wgpu.StorageTextureBindingLayout{
                    access = .ReadOnly,
                    format = .R32Uint,
                    viewDimension = ._2D,
                }
            },
            wgpu.BindGroupLayoutEntry {
                binding = 1,
                visibility = { .Compute },
                storageTexture = wgpu.StorageTextureBindingLayout{
                    access = .ReadOnly,
                    format = .R32Float,
                    viewDimension = ._2D
                }
            },
            wgpu.BindGroupLayoutEntry {
                binding = 2,
                visibility = { .Compute },
                storageTexture = wgpu.StorageTextureBindingLayout{
                    access = .ReadOnly,
                    format = .RGBA32Float,
                    viewDimension = ._2D
                }
            }
        })
    })

    world.bind_group = wgpu.DeviceCreateBindGroup(wgpu_state.device, &wgpu.BindGroupDescriptor{
        entryCount = 3,
        entries = raw_data([]wgpu.BindGroupEntry{
            wgpu.BindGroupEntry{
                binding = 0,
                offset = 0,
                size = u64(WORLD_CELLS) * size_of(u32),
                textureView = wgpu.TextureCreateView(world.density)
            },
            wgpu.BindGroupEntry{
                binding = 1,
                offset = 0,
                size = u64(WORLD_CELLS) * size_of(f32),
                textureView = wgpu.TextureCreateView(world.emission)
            },
            wgpu.BindGroupEntry{
                binding = 2,
                offset = 0,
                size = u64(WORLD_CELLS) * size_of([4]f32),
                textureView = wgpu.TextureCreateView(world.colour)
            }
        }),
        layout = world.layout,
    })

    world_data := generate_world()
    defer free(world_data)

    write_texture :: proc(src: rawptr, dest: wgpu.Texture, cell_size: uint) {
        wgpu.QueueWriteTexture(wgpu_state.queue,
            &wgpu.TexelCopyTextureInfo{
                mipLevel = 0,
                texture = dest,
            },
            src,
            cell_size * uint(WORLD_CELLS),
            &wgpu.TexelCopyBufferLayout{
                bytesPerRow = WORLD_SIZE[0] * u32(cell_size),
                offset = 0,
                rowsPerImage = WORLD_SIZE[1]
            },
            &wgpu.Extent3D{
                depthOrArrayLayers = 1,
                width = WORLD_SIZE[0],
                height = WORLD_SIZE[1],
            }
        )
    }

    write_texture(&world_data.density, world.density, size_of(u32))
    write_texture(&world_data.emission, world.emission, size_of(f32))
    write_texture(&world_data.colour, world.colour, size_of([4]f32))
}

@(private="file")
WorldData :: #soa[WORLD_CELLS]WorldCell

@(private="file")
WorldCell :: struct {
    density: u32,
    emission: f32,
    colour: [4]f32
}

@(private="file")
generate_world :: proc() -> (data: ^WorldData) {
    data = new(WorldData)

    fill_cell :: proc(cell: u32, world: ^WorldData) {
        if rand.uint32() % 10 != 0 {
            cell := &world[cell]
            cell.density = 1
            cell.colour = { 1., 1., 1., 0., }
        }
    }

    cells := uint(math.sqrt(f64(WORLD_CELLS)))

    for cell in 0..<cells {
        width, height := rand.uint32() % 10 + 5, rand.uint32() % 10 + 5
        x, y := rand.uint32() % (WORLD_SIZE.x - width), rand.uint32() %(WORLD_SIZE.y - height)

        for i in 0..=width {
            fill_cell(y * WORLD_SIZE.y + x + i, data)
        }
        for i in 0..=width {
            fill_cell((y + height) * WORLD_SIZE.y + x + i, data)
        }
        for i in 0..=height {
            fill_cell((y + i) * WORLD_SIZE.y + x, data)
        }
        for i in 0..=height {
            fill_cell((y + i) * WORLD_SIZE.y + x + width, data)
        }
    }

    for y in 0..<WORLD_SIZE[1] {
        for x in 0..<WORLD_SIZE[0] {
            if rand.uint32() % 100 == 0 {
                cell := &data[y * WORLD_SIZE[1] + x]

                // emission_fac := max(rand.float32() - 0.5, 0.) * 2.

                cell.density = 1
                cell.emission = 1.
                cell.colour = { 1., 1., 1., 0., }
            }
        }
    }

    return
}