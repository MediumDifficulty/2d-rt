package rt_2d

import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"
import "base:runtime"
import "core:math/rand"

state: struct {
    os: OS
}

pipeline_state : struct {
    module: wgpu.ShaderModule,
    pipeline: wgpu.RenderPipeline,
    pipeline_layout: wgpu.PipelineLayout,

    uniform_layout: wgpu.BindGroupLayout,
    uniform_bind_group: wgpu.BindGroup,
    uniform_buffer: wgpu.Buffer,
    camera: CameraUniform
}

CameraUniform :: struct {
    resolution: [2]f32,
    centre: linalg.Vector2f32,
    zoom: f32,
    _padding: [8]u8
}

PixelWorld :: struct {
    density: wgpu.Texture,
    emission: wgpu.Texture,

    layout: wgpu.BindGroupLayout,
    bind_group: wgpu.BindGroup
}

main :: proc () {
    // fmt.println(context.random_generator.procedure)

    os_init()
    wgpu_init(on_wgpu)

    on_wgpu :: proc() {
        fmt.println(size_of(CameraUniform))

        world_init()

        fmt.println("WGPU initialized")
        shader :: string(#load("shader/shader.wgsl"))

        pipeline_state.module = wgpu.DeviceCreateShaderModule(wgpu_state.device, &wgpu.ShaderModuleDescriptor{
            nextInChain = &wgpu.ShaderSourceWGSL {
                sType = .ShaderSourceWGSL,
                code = shader,
            }
        })

        pipeline_state.uniform_buffer = wgpu.DeviceCreateBuffer(wgpu_state.device, &wgpu.BufferDescriptor{
            size = size_of(CameraUniform),
            usage = { .Uniform, .CopyDst },
            mappedAtCreation = false,
        })

        pipeline_state.uniform_layout = wgpu.DeviceCreateBindGroupLayout(wgpu_state.device, &wgpu.BindGroupLayoutDescriptor{
            label = "bind_group_layout",
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

        pipeline_state.uniform_bind_group = wgpu.DeviceCreateBindGroup(wgpu_state.device, &wgpu.BindGroupDescriptor{
            layout = pipeline_state.uniform_layout,
            entryCount = 1,
            entries = raw_data([]wgpu.BindGroupEntry{
                wgpu.BindGroupEntry{
                    binding = 0,
                    buffer = pipeline_state.uniform_buffer,
                    size = size_of(CameraUniform),
                }
            }),
        })

        pipeline_state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(wgpu_state.device, &wgpu.PipelineLayoutDescriptor{
            bindGroupLayoutCount = 2,
            bindGroupLayouts = raw_data([]wgpu.BindGroupLayout{ pipeline_state.uniform_layout, world.layout }),
        })

        pipeline_state.pipeline = wgpu.DeviceCreateRenderPipeline(wgpu_state.device, &wgpu.RenderPipelineDescriptor{
            layout = pipeline_state.pipeline_layout,
            vertex = {
                module = pipeline_state.module,
                entryPoint = "vs_main",
            },
            fragment = &{
                module = pipeline_state.module,
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

        pipeline_state.camera.zoom = 1.;
        pipeline_state.camera.resolution = { f32(wgpu_state.config.width), f32(wgpu_state.config.height) }

        fmt.println(pipeline_state.camera)

        os_run()
    }
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

    render_pass(frame)
    
    wgpu.SurfacePresent(wgpu_state.surface)
}

render_pass :: proc(frame: wgpu.TextureView) {
    command_encoder := wgpu.DeviceCreateCommandEncoder(wgpu_state.device, nil)
    defer wgpu.CommandEncoderRelease(command_encoder)


    wgpu.QueueWriteBuffer(wgpu_state.queue, pipeline_state.uniform_buffer, 0, &pipeline_state.camera, size_of(CameraUniform))

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

    wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, pipeline_state.pipeline)
    wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, pipeline_state.uniform_bind_group)
    wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 1, world.bind_group)

    wgpu.RenderPassEncoderDraw(render_pass_encoder, 3, 1, 0, 0)

    wgpu.RenderPassEncoderEnd(render_pass_encoder)
    wgpu.RenderPassEncoderRelease(render_pass_encoder)

    command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
    defer wgpu.CommandBufferRelease(command_buffer)
    
    wgpu.QueueSubmit(wgpu_state.queue, { command_buffer })
}

render_pipeline_finish :: proc() {
	wgpu.RenderPipelineRelease(pipeline_state.pipeline)
	wgpu.PipelineLayoutRelease(pipeline_state.pipeline_layout)
    
	wgpu.ShaderModuleRelease(pipeline_state.module)
}

resize :: proc "c" () {
    context = wgpu_state.ctx

    fmt.println("Resized")
    pipeline_state.camera.resolution = { f32(wgpu_state.config.width), f32(wgpu_state.config.height) }
    wgpu_state.config.width, wgpu_state.config.height = os_get_framebuffer_size()
    wgpu.SurfaceConfigure(wgpu_state.surface, &wgpu_state.config)
}

finish :: proc "c" () {
    context = wgpu_state.ctx


    render_pipeline_finish()
    wgpu_finish()
}