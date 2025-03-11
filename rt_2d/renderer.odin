package rt_2d

import "vendor:wgpu"
import "core:fmt"
import "base:runtime"

wgpu_state : struct {
    ctx: runtime.Context,

    instance: wgpu.Instance,
    surface: wgpu.Surface,
    adapter: wgpu.Adapter,
    device: wgpu.Device,
    queue: wgpu.Queue,

    surface_caps: wgpu.SurfaceCapabilities,
    config: wgpu.SurfaceConfiguration,
}

@(private="file")
cb: proc()

wgpu_init :: proc (callback: proc()) {
    wgpu_state.ctx = context

    cb = callback
    wgpu_state.instance = wgpu.CreateInstance(nil)

    if wgpu_state.instance == nil {
        panic("Failed to create WGPU instance")
    }

    wgpu_state.surface = os_get_surface(wgpu_state.instance)

    wgpu.InstanceRequestAdapter(wgpu_state.instance, &{ compatibleSurface = wgpu_state.surface }, { callback = on_adapter })

    on_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: string, userdata1: rawptr, userdata2: rawptr) {
        context = wgpu_state.ctx
        if status != .Success || adapter == nil {
            panic("Failed to request WGPU adapter")
        }
        info, status := wgpu.AdapterGetInfo(adapter)

        fmt.println("Adapter:", info, "Status:", status)

        wgpu_state.adapter = adapter
        
        wgpu.AdapterRequestDevice(adapter, &wgpu.DeviceDescriptor{
            requiredFeatureCount = 1,
            requiredFeatures = raw_data([]wgpu.FeatureName{
                wgpu.FeatureName.TextureAdapterSpecificFormatFeatures
            }),
            // requiredLimits = &wgpu.Limits {
            //     // maxBindGroups = 128,
            // }
        }, { callback = on_device})
    }

    on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1: rawptr, userdata2: rawptr) {
        context = wgpu_state.ctx
        if status != .Success || device == nil {
            panic("Failed to request WGPU device")
        }
        wgpu_state.device = device

        width, height := os_get_framebuffer_size()

        surface_caps, surf_ok := wgpu.SurfaceGetCapabilities(wgpu_state.surface, wgpu_state.adapter)

        wgpu_state.config = wgpu.SurfaceConfiguration {
            device = wgpu_state.device,
            usage = { .RenderAttachment },
            format = surface_caps.formats[0],
            width = width,
            height = height,
            presentMode = .Fifo,
            alphaMode = .Opaque,
        }
        wgpu.SurfaceConfigure(wgpu_state.surface, &wgpu_state.config)

        wgpu_state.queue = wgpu.DeviceGetQueue(wgpu_state.device)
        wgpu_state.surface_caps = surface_caps

        cb()
    }
}

wgpu_finish :: proc () {
    wgpu.QueueRelease(wgpu_state.queue)
	wgpu.DeviceRelease(wgpu_state.device)
	wgpu.AdapterRelease(wgpu_state.adapter)
	wgpu.SurfaceRelease(wgpu_state.surface)
    wgpu.InstanceRelease(wgpu_state.instance)
}