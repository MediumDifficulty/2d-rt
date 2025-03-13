package rt_2d

import "vendor:wgpu"
import "core:math/linalg"
import "core:math/rand"

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
        entryCount = 2,
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
        entryCount = 2,
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
                size = u64(WORLD_CELLS) * size_of(f32),
                textureView = wgpu.TextureCreateView(world.emission)
            }
        }),
        layout = world.layout,
    })

    data := new(#soa[WORLD_CELLS]struct {
        density: u32,
        emission: f32,
        colour: [4]f32
    })
    defer free(data)

    for y in 0..<WORLD_SIZE[1] {
        for x in 0..<WORLD_SIZE[0] {
            if rand.uint32() % 10 == 0 {
                cell := &data[y * WORLD_SIZE[1] + x]

                emission_fac := max(rand.float32() - 0.5, 0.) * 2.

                cell.density = 1
                cell.emission = emission_fac
            }
        }
    }

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

    write_texture(&data.density, world.density, size_of(u32))
    write_texture(&data.emission, world.emission, size_of(f32))
    write_texture(&data.colour, world.colour, size_of([4]f32))
}
