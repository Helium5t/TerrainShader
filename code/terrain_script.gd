@tool
class_name HeliumTerrain extends CompositorEffect

@export var create_fb : bool = true

@export_group("Rendering")
@export var show_wireframe : bool = false
@export_range(0.00, 5.0, 0.01) var displacement_amt : float = 0.0
@export var noise_seed : int = 1

@export_group("Mesh Generation")
@export var dynamic_mesh : bool = false

@export_range(2,1000, 1, "or_greater") var vertex_density : int = 5

@export_range(0.01, 1.0, 0.01, "or_greater") var plane_scale : float = 1.0

# Geometry and Scene vars (for Uniforms)
var transform : Transform3D
var main_light : DirectionalLight3D

# Device Level (GPU) vars
var r_device : RenderingDevice

var shader_id : RID
var device_v_buffer : RID
var device_v_array : RID
var device_idx_buffer : RID
var device_idx_array : RID
var device_ubo_buffer : RID
var device_ubo_array : RID
var device_uniform_set : RID
var device_render_pipeline : RID
var device_framebuffer : RID


var clear_cols := PackedColorArray([Color(0.05,0.2,0.05,1.0)])
var v_format : int

func _init():
    effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    r_device = RenderingServer.get_rendering_device()

    var tree := Engine.get_main_loop()
    var root_node : Node = tree.edited_scene_root if Engine.is_editor_hint() else tree.current_scene
    if root_node:
        main_light = root_node.get_node_or_null('DirectionaLight3D')


func compile_shaders(v_s : String, f_s : String) -> RID:
    var shader_source_code := RDShaderSource.new()
    shader_source_code.source_vertex = v_s
    shader_source_code.source_fragment = f_s

    var spirv : RDShaderSPIRV = r_device.shader_compile_spirv_from_source(shader_source_code)

    var err = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_VERTEX)
    if err: 
        push_error(err)
    assert(!err, "Failed to compile vertex shader")
    err = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_FRAGMENT)
    if err:
        push_error(err)
    assert(!err, "Failed to compile fragment shader")

    return r_device.shader_create_from_spirv(spirv)


func load_shaders() -> Array[String]:
    var vertex_path : String =   "res://code/terrain.v"
    var fragment_path : String = "res://code/terrain.f"
    assert(FileAccess.file_exists(vertex_path), "vertex shader does not exist")
    var file = FileAccess.open(vertex_path, FileAccess.READ)
    var v = file.get_as_text()
    file.close()
    assert(FileAccess.file_exists(fragment_path), "fragment shader does not exist")
    file = FileAccess.open(fragment_path, FileAccess.READ)
    var f = file.get_as_text()
    file.close()
    return [v, f]

func create_vertices() -> Array[Array]:
    if not dynamic_mesh:
        return [PackedFloat32Array(
            [-0.5, 0, 0.5,
             -0.5, 0, -0.5,
             0.5, 0, -0.5,
             0.5, 0, 0.5,]
        ), PackedInt32Array([
            0,1,2,2,3,0
        ])]
    var v := []
    var i := []
    var offset := (vertex_density-1) * plane_scale / 2.0
    for x in vertex_density:
        for z in vertex_density:
            v.append_array([plane_scale*x - offset, 0, plane_scale*z - offset ])
            if x==0 or z == 0:
                continue
            i.append_array([x*vertex_density + z, (x-1)*vertex_density + z, (x-1)*vertex_density + z -1])
            i.append_array([(x-1)*vertex_density + z -1, x*vertex_density + z -1, x*vertex_density + z])
    return [v,i]
    

func create_vertex_and_index_buffers():
    # Vertex
    var buffers := create_vertices()
    var v_buffer : PackedFloat32Array = buffers[0]
    var i_buffer : PackedInt32Array = buffers[1]

    var v_count = v_buffer.size() / 3

    var v_buffer_b : PackedByteArray = v_buffer.to_byte_array()
    device_v_buffer = r_device.vertex_buffer_create(v_buffer_b.size(), v_buffer_b)
    assert(device_v_buffer.is_valid() && device_v_buffer.get_id() != 0, "invalid device vertex buffer")
    
    var v_buffer_attr = [RDVertexAttribute.new()]
    v_buffer_attr[0].format = r_device.DATA_FORMAT_R32G32B32_SFLOAT
    v_buffer_attr[0].frequency = RenderingDevice.VERTEX_FREQUENCY_VERTEX
    v_buffer_attr[0].location = 0
    v_buffer_attr[0].offset = 0
    v_buffer_attr[0].stride = 3 * 4 # 4 bytes * 3 floats  

    v_format = r_device.vertex_format_create(v_buffer_attr)

    device_v_array = r_device.vertex_array_create(v_count, v_format, [device_v_buffer])
    assert(device_v_array.is_valid() and device_v_array.get_id() != 0, "vertex array null?")

    # Index buffer
    var index_buffer_b : PackedByteArray = i_buffer.to_byte_array()

    device_idx_buffer = r_device.index_buffer_create(i_buffer.size(), r_device.INDEX_BUFFER_FORMAT_UINT32, index_buffer_b)

    device_idx_array = r_device.index_array_create(device_idx_buffer, 0, i_buffer.size())

func create_bind_uniform_buffers(render_data: RenderData):

    var ubo_buffer = [];
    var model = transform
    var scene_data : RenderSceneDataRD = render_data.get_render_scene_data() # used for getting the mvp matrix from godot
    var view = scene_data.get_cam_transform().inverse()
    var proj = scene_data.get_view_projection(0)

    var obj_to_view = Projection(view * model)
    var obj_to_clip = proj * obj_to_view

    # Push values to host buffer
    for i in range(0, 16):
        ubo_buffer.push_back(obj_to_clip[i/4][i%4])
    ubo_buffer.push_back(displacement_amt * plane_scale)
    ubo_buffer.push_back(noise_seed)

    # in std140 the base alignment (the one dictating the size) is always 4N, so the size of the buffer
    # always has to be a multiple of 16
    while ubo_buffer.size() % 4 != 0: 
        ubo_buffer.push_back(0)
    #### 

    var ubo_buffer_b = PackedFloat32Array(ubo_buffer).to_byte_array()
    device_ubo_buffer = r_device.uniform_buffer_create(ubo_buffer_b.size(), ubo_buffer_b)
    var uniforms = []
    var ubo := RDUniform.new()
    ubo.binding = 0
    ubo.uniform_type = r_device.UNIFORM_TYPE_UNIFORM_BUFFER
    ubo.add_id(device_ubo_buffer)
    
    # Push host buffer to device
    uniforms.push_back(ubo)
    #####
    assert(len(uniforms) > 0, "uniform array is empty");

    if device_uniform_set.is_valid():
        r_device.free_rid(device_uniform_set)
    device_uniform_set = r_device.uniform_set_create(uniforms, shader_id, 0)
    assert(device_uniform_set.get_id() != 0, "uniform set is 0");
        

    

        
func create_bind_buffers(render_data : RenderData):
    create_vertex_and_index_buffers()
    create_bind_uniform_buffers(render_data)

func init_render(framebuffer_format : int, render_data : RenderData):
    var shader_sources = load_shaders()
    assert(shader_sources[0] != null, "idk?")
    shader_id = compile_shaders(shader_sources[0], shader_sources[1])

    create_bind_buffers(render_data)
    create_pipeline(framebuffer_format)


func create_pipeline(format : int) -> void:
    var rasterization = RDPipelineRasterizationState.new()
    rasterization.cull_mode = RenderingDevice.POLYGON_CULL_DISABLED
    rasterization.wireframe = show_wireframe
    rasterization.enable_depth_clamp = false
    rasterization.line_width = 1.0;
    rasterization.front_face = RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE
    rasterization.depth_bias_enabled = false

    var depth = RDPipelineDepthStencilState.new()
    depth.enable_depth_write = true
    depth.enable_depth_test = true
    depth.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER

    var color_attachment = RDPipelineColorBlendStateAttachment.new()
    color_attachment.enable_blend = true
    color_attachment.write_a = true
    color_attachment.write_b = true
    color_attachment.write_g = true
    color_attachment.write_r = true
    color_attachment.alpha_blend_op = RenderingDevice.BLEND_OP_ADD
    color_attachment.color_blend_op = RenderingDevice.BLEND_OP_ADD
    color_attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
    color_attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ZERO
    color_attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
    color_attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ZERO
    var blending = RDPipelineColorBlendState.new()
    blending.enable_logic_op = false
    blending.logic_op = RenderingDevice.LOGIC_OP_NO_OP
    blending.attachments.push_back(color_attachment)

    var multisampling = RDPipelineMultisampleState.new()
    multisampling.enable_sample_shading = false
    multisampling.sample_count = RenderingDevice.TEXTURE_SAMPLES_1
    multisampling.min_sample_shading = 1.0
    
    device_render_pipeline = r_device.render_pipeline_create(shader_id, format, v_format, r_device.RENDER_PRIMITIVE_TRIANGLES, rasterization, multisampling, depth, blending)


func create_device_uniforms():
    pass

func build_bind_draw_commands():
    r_device.draw_command_begin_label("Terrain", Color(1.0,0.0,0.0,1.0))

    var draw_list = r_device.draw_list_begin(device_framebuffer, r_device.DRAW_DEFAULT_ALL, clear_cols, 1.0,0 , Rect2(), 0)

    r_device.draw_list_bind_render_pipeline(draw_list, device_render_pipeline)
    
    # Buffers
    r_device.draw_list_bind_vertex_array(draw_list, device_v_array)
    r_device.draw_list_bind_index_array(draw_list, device_idx_array)
    r_device.draw_list_bind_uniform_set(draw_list, device_uniform_set, 0)

    r_device.draw_list_draw(draw_list, true, 1, 0)

    r_device.draw_list_end()
    r_device.draw_command_end_label()


        
func free_all():
    print("freeing memory")
    if device_render_pipeline.is_valid():
        r_device.free_rid(device_render_pipeline)
    if device_v_array.is_valid():
        r_device.free_rid(device_v_array)
    if device_v_buffer.is_valid():
        r_device.free_rid(device_v_buffer)
    if device_idx_array.is_valid():
        r_device.free_rid(device_idx_array)
    if device_idx_buffer.is_valid():
        r_device.free_rid(device_idx_buffer)
    if shader_id.is_valid():
        r_device.free_rid(shader_id)
    if device_framebuffer.is_valid():
        r_device.free_rid(device_framebuffer)

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        free_all()
    



func _render_callback(callback_type: int, render_data: RenderData) -> void:
    if not enabled: return
    if callback_type != effect_callback_type: return

    var scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()  

    if not scene_buffers : return

    if not device_render_pipeline.is_valid():
        _notification(NOTIFICATION_PREDELETE)
        var fb_format := 0
        if not create_fb:
            device_framebuffer = FramebufferCacheRD.get_cache_multipass([scene_buffers.get_color_texture(), scene_buffers.get_depth_texture()], [], 1)
            fb_format = r_device.framebuffer_get_format(device_framebuffer)
        else:
            var color_tex = scene_buffers.get_color_texture()
            var depth_tex = scene_buffers.get_depth_texture()
            device_framebuffer = r_device.framebuffer_create([color_tex, depth_tex])
            fb_format = r_device.framebuffer_get_format(device_framebuffer)
        init_render(fb_format, render_data)

    var cur_framebuffer = FramebufferCacheRD.get_cache_multipass([scene_buffers.get_color_texture(), scene_buffers.get_depth_texture()], [], 1)

    if device_framebuffer != cur_framebuffer:
        device_framebuffer = cur_framebuffer
        var fb_format := 0
        if create_fb:
            var color_tex = scene_buffers.get_color_texture()
            var depth_tex = scene_buffers.get_depth_texture()
            device_framebuffer = r_device.framebuffer_create([color_tex, depth_tex])
            fb_format = r_device.framebuffer_get_format(device_framebuffer)
        else:
            fb_format=r_device.framebuffer_get_format(device_framebuffer)
        init_render(fb_format, render_data)
    
    create_device_uniforms()

    build_bind_draw_commands()
