package rt_2d

import "vendor:wgpu"
import "core:math/linalg"
import "core:math/rand"

WORLD_SIZE :: [2]u32{128, 128}
WORLD_CELLS :: WORLD_SIZE[0] * WORLD_SIZE[1]

world: PixelWorld

world_init :: proc() {
    world.density = wgpu.DeviceCreateTexture(wgpu_state.device, &wgpu.TextureDescriptor{
        size = wgpu.Extent3D{
            width = WORLD_SIZE[0],
            height = WORLD_SIZE[1],
            depthOrArrayLayers = 1
        },
        mipLevelCount = 1,
        sampleCount = 1,
        dimension = ._2D,
        format = .R32Uint,
        usage = { .StorageBinding, .CopyDst },

    })

    world.emission = wgpu.DeviceCreateTexture(wgpu_state.device, &wgpu.TextureDescriptor{
        size = wgpu.Extent3D{
            width = WORLD_SIZE[0],
            height = WORLD_SIZE[1],
            depthOrArrayLayers = 1
        },
        mipLevelCount = 1,
        sampleCount = 1,

        dimension = ._2D,
        format = .R32Float,
        usage = { .StorageBinding, .CopyDst }
    })

    world.layout = wgpu.DeviceCreateBindGroupLayout(wgpu_state.device, &wgpu.BindGroupLayoutDescriptor{
        entryCount = 2,
        entries = raw_data([]wgpu.BindGroupLayoutEntry{
            wgpu.BindGroupLayoutEntry {
                binding = 0,
                visibility = { .Fragment },
                storageTexture = wgpu.StorageTextureBindingLayout{
                    access = .ReadOnly,
                    format = .R32Uint,
                    viewDimension = ._2D,
                }
            },
            wgpu.BindGroupLayoutEntry {
                binding = 1,
                visibility = { .Fragment },
                storageTexture = wgpu.StorageTextureBindingLayout{
                    access = .ReadOnly,
                    format = .R32Float,
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
            }
        }),
        layout = world.layout,
    })

    density: [WORLD_CELLS]u32
    emission: [WORLD_CELLS]f32

    rand.reset(1)
    
    for y in 0..<WORLD_SIZE[1] {
        for x in 0..<WORLD_SIZE[0] {
            if rand.uint32() % 10 == 0 {
                emission_fac := max(rand.float32() - 0.5, 0.) * 2.

                density[y * WORLD_SIZE[1] + x] = 1
                emission[y * WORLD_SIZE[1] + x] = emission_fac
            }
        }
    }

    wgpu.QueueWriteTexture(wgpu_state.queue,
        &wgpu.TexelCopyTextureInfo{
            mipLevel = 0,
            texture = world.density,
        },
        &density,
        size_of(density),
        &wgpu.TexelCopyBufferLayout{
            bytesPerRow = WORLD_SIZE[0] * size_of(u32),
            offset = 0,
            rowsPerImage = WORLD_SIZE[1]
        },
        &wgpu.Extent3D{
            depthOrArrayLayers = 1,
            width = WORLD_SIZE[0],
            height = WORLD_SIZE[1],
        }
    )

    wgpu.QueueWriteTexture(wgpu_state.queue,
        &wgpu.TexelCopyTextureInfo{
            mipLevel = 0,
            texture = world.emission,
        },
        &emission,
        size_of(density),
        &wgpu.TexelCopyBufferLayout{
            bytesPerRow = WORLD_SIZE[0] * size_of(f32),
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