package rt_2d

import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"
import "base:runtime"
import "core:math/rand"

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

shared_textures : struct {
    textures: [2]struct {
        surface_texture: wgpu.Texture,
        view: wgpu.TextureView,
        compute_bind_group: wgpu.BindGroup,
        render_bind_group: wgpu.BindGroup,
    },

    compute_layout: wgpu.BindGroupLayout,
    render_layout: wgpu.BindGroupLayout,

    polarity: bool
}

CameraUniform :: struct {
    resolution: [2]f32,
    centre: linalg.Vector2f32,
    zoom: f32,
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
        shared_texture_init()

        compute_init()
        renderer_init()

        fmt.println("Finished init")
        // fmt.println(pipeline_state.camera)

        os_run()
    }
}

shared_texture_init :: proc() {
    for &texture, i in shared_textures.textures {
        texture.surface_texture = wgpu.DeviceCreateTexture(wgpu_state.device, &wgpu.TextureDescriptor{
            size = wgpu.Extent3D{
                width = wgpu_state.config.width,
                height = wgpu_state.config.height,
                depthOrArrayLayers = 1
            },
            mipLevelCount = 1,
            sampleCount = 1,
    
            dimension = ._2D,
            format = .RGBA32Float,
            usage = { .StorageBinding }
        })

        texture.view = wgpu.TextureCreateView(shared_textures.textures[i].surface_texture, nil)
    }

    shared_textures.compute_layout = wgpu.DeviceCreateBindGroupLayout(wgpu_state.device, &wgpu.BindGroupLayoutDescriptor{
        entryCount = 2,
        entries = raw_data([]wgpu.BindGroupLayoutEntry{
            wgpu.BindGroupLayoutEntry{
                binding = 0,
                visibility = { .Compute },
                storageTexture = wgpu.StorageTextureBindingLayout{
                    access = wgpu.StorageTextureAccess.ReadOnly,
                    format = wgpu.TextureFormat.RGBA32Float,
                    viewDimension = wgpu.TextureViewDimension._2D
                }
            },
            wgpu.BindGroupLayoutEntry{
                binding = 1,
                visibility = { .Compute },
                storageTexture = wgpu.StorageTextureBindingLayout{
                    access = wgpu.StorageTextureAccess.WriteOnly,
                    format = wgpu.TextureFormat.RGBA32Float,
                    viewDimension = wgpu.TextureViewDimension._2D
                }
            }
        })
    })

    shared_textures.render_layout = wgpu.DeviceCreateBindGroupLayout(wgpu_state.device, &wgpu.BindGroupLayoutDescriptor{
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

    for &texture, i in shared_textures.textures {
        texture_size := size_of([4]f32) * u64(wgpu_state.config.width * wgpu_state.config.height)
        texture.compute_bind_group = wgpu.DeviceCreateBindGroup(wgpu_state.device, &wgpu.BindGroupDescriptor{
            layout = shared_textures.compute_layout,
            entryCount = 2,
            entries = raw_data([]wgpu.BindGroupEntry{
                wgpu.BindGroupEntry{
                    binding = 0,
                    textureView = shared_textures.textures[1 - i].view,
                    offset = 0,
                    size = texture_size,
                },
                wgpu.BindGroupEntry{
                    binding = 1,
                    textureView = shared_textures.textures[i].view,
                    offset = 0,
                    size = texture_size,
                }
            })
        })

        texture.render_bind_group = wgpu.DeviceCreateBindGroup(wgpu_state.device, &wgpu.BindGroupDescriptor{
            layout = shared_textures.render_layout,
            entryCount = 1,
            entries = raw_data([]wgpu.BindGroupEntry{
                wgpu.BindGroupEntry{
                    binding = 0,
                    textureView = shared_textures.textures[i].view,
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
        bindGroupLayouts = raw_data([]wgpu.BindGroupLayout{ shared_textures.compute_layout, world.layout, compute_pipeline_state.uniform_layout }),
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
        bindGroupLayouts = raw_data([]wgpu.BindGroupLayout{ shared_textures.render_layout, renderer_pipeline_state.uniform_layout })
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

    frame := wgpu.TextureCreateView(surface_texture.texture, nil)
    defer wgpu.TextureViewRelease(frame)

    compute_pass()
    viewport_pass(frame)
    
    shared_textures.polarity = !shared_textures.polarity

    wgpu.SurfacePresent(wgpu_state.surface)
}

compute_pass :: proc() {
    wgpu.QueueWriteBuffer(wgpu_state.queue, compute_pipeline_state.uniform_buffer, 0, &compute_pipeline_state.camera, size_of(CameraUniform))

    command_encoder := wgpu.DeviceCreateCommandEncoder(wgpu_state.device, nil)
    defer wgpu.CommandEncoderRelease(command_encoder)

    compute_pass_encoder := wgpu.CommandEncoderBeginComputePass(command_encoder, &wgpu.ComputePassDescriptor{

    })

    wgpu.ComputePassEncoderSetPipeline(compute_pass_encoder, compute_pipeline_state.pipeline)
    wgpu.ComputePassEncoderSetBindGroup(compute_pass_encoder, 0, shared_textures.textures[uint(shared_textures.polarity)].compute_bind_group)
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
    wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, shared_textures.textures[uint(shared_textures.polarity)].render_bind_group)
    wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 1, renderer_pipeline_state.uniform_bind_group)

    wgpu.RenderPassEncoderDraw(render_pass_encoder, 3, 1, 0, 0)

    wgpu.RenderPassEncoderEnd(render_pass_encoder)
    wgpu.RenderPassEncoderRelease(render_pass_encoder)

    command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
    defer wgpu.CommandBufferRelease(command_buffer)

    wgpu.QueueSubmit(wgpu_state.queue, { command_buffer })
}

render_pipeline_finish :: proc() {
	wgpu.RenderPipelineRelease(renderer_pipeline_state.pipeline)
	wgpu.PipelineLayoutRelease(renderer_pipeline_state.pipeline_layout)
    
	wgpu.ShaderModuleRelease(renderer_pipeline_state.module)
}

resize :: proc "c" () {
    context = wgpu_state.ctx

    fmt.println("Resized")
    compute_pipeline_state.camera.resolution = { f32(wgpu_state.config.width), f32(wgpu_state.config.height) }
    wgpu_state.config.width, wgpu_state.config.height = os_get_framebuffer_size()
    wgpu.SurfaceConfigure(wgpu_state.surface, &wgpu_state.config)
}

finish :: proc "c" () {
    context = wgpu_state.ctx

    render_pipeline_finish()
    wgpu_finish()
}