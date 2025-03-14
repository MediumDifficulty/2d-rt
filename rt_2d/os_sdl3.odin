#+build !js
package rt_2d

import SDL "vendor:sdl3"
import "core:fmt"
import "core:c"
import "vendor:wgpu/sdl3glue"
import "vendor:wgpu"

OS :: struct {
	window: ^SDL.Window,
}

os_init :: proc() {
    // sdl2.InitFlag.VIDEO
    if !SDL.Init({.VIDEO}) {
        panic("Failed to initialize SDL2")
    }

    state.os.window = SDL.CreateWindow(
        "2D RT",
        800,
        600,
        {.RESIZABLE, .HIGH_PIXEL_DENSITY}
    )

    if state.os.window == nil {
        panic("Failed to create window")
    }
}

os_run :: proc () {
    main_loop: for {
        e: SDL.Event
        compute_pipeline_state.camera.moved = 0
        for SDL.PollEvent(&e) {
            #partial switch e.type {
                case .QUIT:
                    break main_loop
                case .WINDOW_RESIZED, .WINDOW_PIXEL_SIZE_CHANGED:
                    resize()
                case .KEY_DOWN:
                    if e.key.key == SDL.K_ESCAPE {
                        break main_loop
                    }
                    if e.key.key == SDL.K_W {
                        compute_pipeline_state.camera.centre[1] -= compute_pipeline_state.camera.zoom * 10.
                        compute_pipeline_state.camera.moved = 1
                    }
                    if e.key.key == SDL.K_S {
                        compute_pipeline_state.camera.centre[1] += compute_pipeline_state.camera.zoom * 10.
                        compute_pipeline_state.camera.moved = 1
                    }
                    if e.key.key == SDL.K_A {
                        compute_pipeline_state.camera.centre[0] -= compute_pipeline_state.camera.zoom * 10.
                        compute_pipeline_state.camera.moved = 1
                    }
                    if e.key.key == SDL.K_D {
                        compute_pipeline_state.camera.centre[0] += compute_pipeline_state.camera.zoom * 10.
                        compute_pipeline_state.camera.moved = 1
                    }
                case .MOUSE_WHEEL:
                    if e.wheel.y < 0 {
                        compute_pipeline_state.camera.zoom *= 1.1
                        compute_pipeline_state.camera.moved = 1
                    } else {
                        compute_pipeline_state.camera.zoom /= 1.1
                        compute_pipeline_state.camera.moved = 1
                    }
            }
        }
        
        frame()
    }

    finish()

    SDL.DestroyWindow(state.os.window)
    SDL.Quit()
}

os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
    return sdl3glue.GetSurface(instance, state.os.window)
}

os_get_framebuffer_size :: proc() -> (width, height: u32) {
    iw, ih: i32
    SDL.GetWindowSize(state.os.window, &iw, &ih)
    return u32(iw), u32(ih)
}
