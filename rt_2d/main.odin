package rt_2d

import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"
import "base:runtime"
import "core:math/rand"
import "core:time"

state: struct {
    os: OS
}

compute_pipeline_state : struct {
    module: wgpu.ShaderModule,
    pipeline: wgpu.ComputePipeline,
    pipeline_layout: wgpu.PipelineLayout,

    uniform_layout: wgpu.BindGroupLayout,
    uniform_bind_group: wgpu.BindGroup,
    uniform_buffer: wgpu.Buffer,
    camera: CameraUniform
}

renderer_pipeline_state : struct {
    module: wgpu.ShaderModule,
    pipeline: wgpu.RenderPipeline,
    pipeline_layout: wgpu.PipelineLayout,

    uniform_layout: wgpu.BindGroupLayout,
    uniform_bind_group: wgpu.BindGroup,
    uniform_buffer: wgpu.Buffer,
    camera: RendererCameraUniform
}

ViewedTexture :: struct {
    texture: wgpu.Texture,
    view: wgpu.TextureView,
}

screen_space_textures : struct {
    textures: [2]struct {
        surface_texture: ViewedTexture,
        sample_count: ViewedTexture,
        compute_bind_group: wgpu.BindGroup,
    },

    render_bind_groups: [2]wgpu.BindGroup,

    compute_layout: wgpu.BindGroupLayout,
    render_layout: wgpu.BindGroupLayout,

    polarity: bool
}

CameraUniform :: struct {
    resolution: [2]f32,
    centre: linalg.Vector2f32,
    zoom: f32,
    entropy: f32,
    moved: u32, // Acts as a Bool
    _padding: [8]u8
}

RendererCameraUniform :: struct {
    resolution: [2]f32
}

PixelWorld :: struct {
    density: wgpu.Texture,
    emission: wgpu.Texture,
    colour: wgpu.Texture,

    layout: wgpu.BindGroupLayout,
    bind_group: wgpu.BindGroup
}

main :: proc () {
    // fmt.println(context.random_generator.procedure)

    os_init()
    wgpu_init(on_wgpu)

    on_wgpu :: proc() {
        fmt.println("WGPU initialized")

        world_init()
        screen_space_texture_init()

        compute_init()
        renderer_init()

        fmt.println("Finished init")
        // fmt.println(pipeline_state.camera)

        os_run()
    }
}

screen_space_texture_init :: proc() {
    viewed_texture_init :: proc(format: wgpu.TextureFormat) -> ViewedTexture {
        texture := wgpu.DeviceCreateTexture(wgpu_state.device, &wgpu.TextureDescriptor{
            size = wgpu.Extent3D{
                width = wgpu_state.config.width,
                height = wgpu_state.config.height,
                depthOrArrayLayers = 1
            },
            mipLevelCount = 1,
            sampleCount = 1,
    
            dimension = ._2D,
            format = format,
            usage = { .StorageBinding }
        })

        view := wgpu.TextureCreateView(texture)

        return ViewedTexture {
            texture,
            view
        }
    }

    bind_group_layout_entry :: proc(binding: u32, format: wgpu.TextureFormat, read: bool) -> wgpu.BindGroupLayoutEntry {
        return wgpu.BindGroupLayoutEntry{
            binding = binding,
            visibility = { .Compute },
            storageTexture = wgpu.StorageTextureBindingLayout{
                access = wgpu.StorageTextureAccess.ReadOnly if read else wgpu.StorageTextureAccess.WriteOnly,
                format = format,
                viewDimension = wgpu.TextureViewDimension._2D
            }
        }
    }

    bind_group_entry :: proc(binding: u32, view: wgpu.TextureView) -> wgpu.BindGroupEntry {
        texture_size := size_of([4]f32) * u64(wgpu_state.config.width * wgpu_state.config.height)

        return wgpu.BindGroupEntry{
            binding = binding,
            textureView = view,
            offset = 0,
            size = texture_size,
        }
    }

    for &texture, i in screen_space_textures.textures {
        texture.surface_texture = viewed_texture_init(wgpu.TextureFormat.RGBA32Float)
        texture.sample_count = viewed_texture_init(wgpu.TextureFormat.R32Uint)
    }

    screen_space_textures.compute_layout = wgpu.DeviceCreateBindGroupLayout(wgpu_state.device, &wgpu.BindGroupLayoutDescriptor{
        entryCount = 4,
        entries = raw_data([]wgpu.BindGroupLayoutEntry{
            bind_group_layout_entry(0, wgpu.TextureFormat.RGBA32Float, true),
            bind_group_layout_entry(1, wgpu.TextureFormat.RGBA32Float, false),

            bind_group_layout_entry(2, wgpu.TextureFormat.R32Uint, true),
            bind_group_layout_entry(3, wgpu.TextureFormat.R32Uint, false),
        })
    })

    screen_space_textures.render_layout = wgpu.DeviceCreateBindGroupLayout(wgpu_state.device, &wgpu.BindGroupLayoutDescriptor{
        entryCount = 1,
        entries = raw_data([]wgpu.BindGroupLayoutEntry{
            wgpu.BindGroupLayoutEntry{
                binding = 0,
                visibility = { .Fragment },
                storageTexture = wgpu.StorageTextureBindingLayout{
                    access = wgpu.StorageTextureAccess.ReadOnly,
                    format = wgpu.TextureFormat.RGBA32Float,
                    viewDimension = wgpu.TextureViewDimension._2D
                }
            }
        })
    })

    for &texture, i in screen_space_textures.textures {
        texture.compute_bind_group = wgpu.DeviceCreateBindGroup(wgpu_state.device, &wgpu.BindGroupDescriptor{
            layout = screen_space_textures.compute_layout,
            entryCount = 4,
            entries = raw_data([]wgpu.BindGroupEntry{
                bind_group_entry(0, screen_space_textures.textures[1 - i].surface_texture.view),
                bind_group_entry(1, screen_space_textures.textures[    i].surface_texture.view),

                bind_group_entry(2, screen_space_textures.textures[1 - i].sample_count.view),
                bind_group_entry(3, screen_space_textures.textures[    i].sample_count.view),
            })
        })

        texture_size := size_of([4]f32) * u64(wgpu_state.config.width * wgpu_state.config.height)

        screen_space_textures.render_bind_groups[i] = wgpu.DeviceCreateBindGroup(wgpu_state.device, &wgpu.BindGroupDescriptor{
            layout = screen_space_textures.render_layout,
            entryCount = 1,
            entries = raw_data([]wgpu.BindGroupEntry{
                wgpu.BindGroupEntry{
                    binding = 0,
                    textureView = screen_space_textures.textures[i].surface_texture.view,
                    offset = 0,
                    size = texture_size,
                }
            })
        })
    }
}

compute_init :: proc() {
    shader :: string(#load("shader/renderer.wgsl"))

    compute_pipeline_state.module = wgpu.DeviceCreateShaderModule(wgpu_state.device, &wgpu.ShaderModuleDescriptor{
        nextInChain = &wgpu.ShaderSourceWGSL {
            sType = .ShaderSourceWGSL,
            code = shader,
        }
    })

    compute_pipeline_state.uniform_buffer = wgpu.DeviceCreateBuffer(wgpu_state.device, &wgpu.BufferDescriptor{
        size = size_of(CameraUniform),
        usage = { .Uniform, .CopyDst },
        mappedAtCreation = false,
    })

    compute_pipeline_state.uniform_layout = wgpu.DeviceCreateBindGroupLayout(wgpu_state.device, &wgpu.BindGroupLayoutDescriptor{
        label = "bind_group_layout",
        entryCount = 1,
        entries = raw_data([]wgpu.BindGroupLayoutEntry{
            wgpu.BindGroupLayoutEntry{
                binding = 0,
                visibility = { .Compute },
                buffer = wgpu.BufferBindingLayout{
                    type = .Uniform,
                    hasDynamicOffset = false,
                }
            }
        })
    })

    compute_pipeline_state.uniform_bind_group = wgpu.DeviceCreateBindGroup(wgpu_state.device, &wgpu.BindGroupDescriptor{
        layout = compute_pipeline_state.uniform_layout,
        entryCount = 1,
        entries = raw_data([]wgpu.BindGroupEntry{
            wgpu.BindGroupEntry{
                binding = 0,
                buffer = compute_pipeline_state.uniform_buffer,
                size = size_of(CameraUniform),
            }
        }),
    })

    compute_pipeline_state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(wgpu_state.device, &wgpu.PipelineLayoutDescriptor{
        bindGroupLayoutCount = 3,
        bindGroupLayouts = raw_data([]wgpu.BindGroupLayout{ screen_space_textures.compute_layout, world.layout, compute_pipeline_state.uniform_layout }),
    })

    compute_pipeline_state.pipeline = wgpu.DeviceCreateComputePipeline(wgpu_state.device, &wgpu.ComputePipelineDescriptor{
        layout = compute_pipeline_state.pipeline_layout,
        compute = wgpu.ProgrammableStageDescriptor{
            constantCount = 0,
            entryPoint = "sample_kernel",
            module = compute_pipeline_state.module,
        },
    })

    compute_pipeline_state.camera.zoom = 1.;
    compute_pipeline_state.camera.resolution = { f32(wgpu_state.config.width), f32(wgpu_state.config.height) }
}

renderer_init :: proc() {
    shader :: string(#load("shader/viewport.wgsl"))


    renderer_pipeline_state.module = wgpu.DeviceCreateShaderModule(wgpu_state.device, &wgpu.ShaderModuleDescriptor{
        nextInChain = &wgpu.ShaderSourceWGSL {
            sType = .ShaderSourceWGSL,
            code = shader,
        }
    })

    renderer_pipeline_state.uniform_buffer = wgpu.DeviceCreateBuffer(wgpu_state.device, &wgpu.BufferDescriptor{
        size = size_of(RendererCameraUniform),
        usage = { .Uniform, .CopyDst },
        mappedAtCreation = false,
    })

    renderer_pipeline_state.uniform_layout = wgpu.DeviceCreateBindGroupLayout(wgpu_state.device, &wgpu.BindGroupLayoutDescriptor{
        entryCount = 1,
        entries = raw_data([]wgpu.BindGroupLayoutEntry{
            wgpu.BindGroupLayoutEntry{
                binding = 0,
                visibility = { .Fragment },
                buffer = wgpu.BufferBindingLayout{
                    type = .Uniform,
                    hasDynamicOffset = false,
                }
            }
        })
    })

    renderer_pipeline_state.uniform_bind_group = wgpu.DeviceCreateBindGroup(wgpu_state.device, &wgpu.BindGroupDescriptor{
        layout = renderer_pipeline_state.uniform_layout,
        entryCount = 1,
        entries = raw_data([]wgpu.BindGroupEntry{
            wgpu.BindGroupEntry{
                binding = 0,
                buffer = renderer_pipeline_state.uniform_buffer,
                size = size_of(RendererCameraUniform),
            }
        }),
    })

    renderer_pipeline_state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(wgpu_state.device, &wgpu.PipelineLayoutDescriptor{
        bindGroupLayoutCount = 2,
        bindGroupLayouts = raw_data([]wgpu.BindGroupLayout{ screen_space_textures.render_layout, renderer_pipeline_state.uniform_layout })
    })

    renderer_pipeline_state.pipeline = wgpu.DeviceCreateRenderPipeline(wgpu_state.device, &wgpu.RenderPipelineDescriptor{
        layout = renderer_pipeline_state.pipeline_layout,
        vertex = {
            module = renderer_pipeline_state.module,
            entryPoint = "vs_main",
        },
        fragment = &{
            module = renderer_pipeline_state.module,
            entryPoint = "fs_main",
            targetCount = 1,
            targets = &wgpu.ColorTargetState {
                format = wgpu_state.config.format,
                writeMask = wgpu.ColorWriteMaskFlags_All
            },
        },
        primitive = {
            topology = .TriangleList,
        },
        multisample = {
            count = 1,
            mask = ~u32(0)
        }
    })

    renderer_pipeline_state.camera.resolution = { f32(wgpu_state.config.width), f32(wgpu_state.config.height) }
}

frame :: proc "c" () {
    context = wgpu_state.ctx

    surface_texture := wgpu.SurfaceGetCurrentTexture(wgpu_state.surface)
    switch surface_texture.status {
        case .SuccessOptimal, .SuccessSuboptimal:
            // Pass
        case .Timeout, .Outdated, .Lost:
            if surface_texture.texture != nil {
                wgpu.TextureRelease(surface_texture.texture)
            }
            resize()
            return
        case .OutOfMemory, .DeviceLost, .Error:
            fmt.panicf("get_current_texture: %v", surface_texture.status)
    }
    defer wgpu.TextureRelease(surface_texture.texture)

    compute_pipeline_state.camera.entropy = f32(time.now()._nsec % 1_000_000) / 1_000_000.

    frame := wgpu.TextureCreateView(surface_texture.texture, nil)
    defer wgpu.TextureViewRelease(frame)

    compute_pass()
    viewport_pass(frame)
    
    screen_space_textures.polarity = !screen_space_textures.polarity

    wgpu.SurfacePresent(wgpu_state.surface)
}

compute_pass :: proc() {
    wgpu.QueueWriteBuffer(wgpu_state.queue, compute_pipeline_state.uniform_buffer, 0, &compute_pipeline_state.camera, size_of(CameraUniform))

    command_encoder := wgpu.DeviceCreateCommandEncoder(wgpu_state.device, nil)
    defer wgpu.CommandEncoderRelease(command_encoder)

    compute_pass_encoder := wgpu.CommandEncoderBeginComputePass(command_encoder, nil)

    wgpu.ComputePassEncoderSetPipeline(compute_pass_encoder, compute_pipeline_state.pipeline)
    wgpu.ComputePassEncoderSetBindGroup(compute_pass_encoder, 0, screen_space_textures.textures[uint(screen_space_textures.polarity)].compute_bind_group)
    wgpu.ComputePassEncoderSetBindGroup(compute_pass_encoder, 1, world.bind_group)
    wgpu.ComputePassEncoderSetBindGroup(compute_pass_encoder, 2, compute_pipeline_state.uniform_bind_group)

    WORKGROUP_SIZE :: 8

    wgpu.ComputePassEncoderDispatchWorkgroups(compute_pass_encoder, wgpu_state.config.width / WORKGROUP_SIZE, wgpu_state.config.height / WORKGROUP_SIZE, 1)

    wgpu.ComputePassEncoderEnd(compute_pass_encoder)
    wgpu.ComputePassEncoderRelease(compute_pass_encoder)

    command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
    defer wgpu.CommandBufferRelease(command_buffer)

    wgpu.QueueSubmit(wgpu_state.queue, { command_buffer })
}

viewport_pass :: proc(frame: wgpu.TextureView) {
    wgpu.QueueWriteBuffer(wgpu_state.queue, renderer_pipeline_state.uniform_buffer, 0, &renderer_pipeline_state.camera, size_of(RendererCameraUniform))

    command_encoder := wgpu.DeviceCreateCommandEncoder(wgpu_state.device, nil)
    defer wgpu.CommandEncoderRelease(command_encoder)

    render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(command_encoder, &wgpu.RenderPassDescriptor{
        colorAttachmentCount = 1,
        colorAttachments = &wgpu.RenderPassColorAttachment {
            view = frame,
            loadOp = .Clear,
            storeOp = .Store,
            depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
            clearValue = { 0, 1, 0, 1 }
        }
    })

    wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, renderer_pipeline_state.pipeline)
    wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, screen_space_textures.render_bind_groups[uint(screen_space_textures.polarity)])
    wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 1, renderer_pipeline_state.uniform_bind_group)

    wgpu.RenderPassEncoderDraw(render_pass_encoder, 3, 1, 0, 0)

    wgpu.RenderPassEncoderEnd(render_pass_encoder)
    wgpu.RenderPassEncoderRelease(render_pass_encoder)

    command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
    defer wgpu.CommandBufferRelease(command_buffer)

    wgpu.QueueSubmit(wgpu_state.queue, { command_buffer })
}

render_pipeline_finish :: proc() {
    wgpu.BufferRelease(renderer_pipeline_state.uniform_buffer)
    wgpu.BindGroupLayoutRelease(renderer_pipeline_state.uniform_layout)
    wgpu.BindGroupRelease(renderer_pipeline_state.uniform_bind_group)

	wgpu.RenderPipelineRelease(renderer_pipeline_state.pipeline)
	wgpu.PipelineLayoutRelease(renderer_pipeline_state.pipeline_layout)
	wgpu.ShaderModuleRelease(renderer_pipeline_state.module)
}

compute_pipeline_finish :: proc() {
    wgpu.BufferRelease(compute_pipeline_state.uniform_buffer)
    wgpu.BindGroupLayoutRelease(compute_pipeline_state.uniform_layout)
    wgpu.BindGroupRelease(compute_pipeline_state.uniform_bind_group)

	wgpu.ComputePipelineRelease(compute_pipeline_state.pipeline)
	wgpu.PipelineLayoutRelease(compute_pipeline_state.pipeline_layout)
	wgpu.ShaderModuleRelease(compute_pipeline_state.module)
}

screen_space_textures_finish :: proc() {
    wgpu.BindGroupLayoutRelease(screen_space_textures.compute_layout)
    wgpu.BindGroupLayoutRelease(screen_space_textures.render_layout)

    for bind_group in screen_space_textures.render_bind_groups {
        wgpu.BindGroupRelease(bind_group)
    }

    release_viewed_texture :: proc(texture: ViewedTexture) {
        wgpu.TextureViewRelease(texture.view)
        wgpu.TextureRelease(texture.texture)
    }

    for texture in screen_space_textures.textures {
        wgpu.BindGroupRelease(texture.compute_bind_group)

        release_viewed_texture(texture.surface_texture)
        release_viewed_texture(texture.sample_count)
    }
}

resize :: proc "c" () {
    context = wgpu_state.ctx

    fmt.println("Resized")
    wgpu_state.config.width, wgpu_state.config.height = os_get_framebuffer_size()

    compute_pipeline_state.camera.resolution  = { f32(wgpu_state.config.width), f32(wgpu_state.config.height) }
    renderer_pipeline_state.camera.resolution = { f32(wgpu_state.config.width), f32(wgpu_state.config.height) }
    

    wgpu.SurfaceConfigure(wgpu_state.surface, &wgpu_state.config)

    screen_space_textures_finish()
    screen_space_texture_init()
}

finish :: proc "c" () {
    context = wgpu_state.ctx

    render_pipeline_finish()
    compute_pipeline_finish()

    screen_space_textures_finish()

    wgpu_finish()
}