"""
JARVIS hologram – Blender procedural scene (Blender 4.2 ~ 5.x)
10초(240프레임 @24fps) 심리스 루프 애니메이션.

사용법:
  1) Blender > Scripting 탭에서 이 파일 열고 Run Script
  2) 또는 터미널:  blender -b -P jarvis_hologram.py -- --save jarvis.blend
"""
import bpy, bmesh, math, random, sys
from mathutils import Vector

FPS = 24
LOOP = 240            # 10초
ORANGE = (1.0, 0.30, 0.02, 1)
AMBER = (1.0, 0.45, 0.08, 1)
HOT = (1.0, 0.85, 0.6, 1)
random.seed(7)

# ------------------------------------------------------------------ 초기화
for ob in list(bpy.data.objects):
    bpy.data.objects.remove(ob, do_unlink=True)
for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.curves, bpy.data.lights, bpy.data.cameras):
    for d in list(coll):
        coll.remove(d)

scn = bpy.context.scene
scn.frame_start, scn.frame_end = 1, LOOP
scn.render.fps = FPS
scn.render.resolution_x, scn.render.resolution_y = 1920, 1080
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        scn.render.engine = eng
        break
    except TypeError:
        pass
try:
    scn.view_settings.view_transform = "AgX"
    scn.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    pass

world = scn.world or bpy.data.worlds.new("World")
scn.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)

ROOT = bpy.data.objects.new("JARVIS_root", None)
scn.collection.objects.link(ROOT)


# ------------------------------------------------------------------ 헬퍼
def link(obj, parent=ROOT):
    scn.collection.objects.link(obj)
    obj.parent = parent
    return obj


def emit_mat(name, color, strength, alpha=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = color
    em.inputs["Strength"].default_value = strength
    if alpha < 1.0:
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.inputs[0].default_value = alpha
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs[0])
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = "BLENDED"
        else:
            m.blend_method = "BLEND"
    else:
        nt.links.new(em.outputs[0], out.inputs[0])
    return m


def drive(target, path, expr, index=-1):
    fc = target.driver_add(path, index) if index >= 0 else target.driver_add(path)
    fc.driver.type = "SCRIPTED"
    fc.driver.expression = expr
    return fc


def spin(obj, turns, axis=2, phase=0.0):
    """LOOP 프레임 동안 정확히 turns 바퀴 → 심리스"""
    drive(obj, "rotation_euler",
          f"{phase} + (frame-1)/{LOOP}*2*pi*{turns}", axis)


def sway(obj, amount, axis=2, cycles=1):
    """심리스 왕복 회전 (amount 라디안)"""
    drive(obj, "rotation_euler", f"{amount}*sin((frame-1)/{LOOP}*2*pi*{cycles})", axis)


def arc_mesh(name, r, width, a0=0.0, a1=360.0, seg=256, z=0.0):
    """평면 고리(annulus) 또는 원호"""
    bm = bmesh.new()
    n = max(4, int(seg * (a1 - a0) / 360))
    full = abs(a1 - a0) >= 359.99
    ring_in, ring_out = [], []
    for i in range(n + (0 if full else 1)):
        a = math.radians(a0 + (a1 - a0) * i / n)
        c, s = math.cos(a), math.sin(a)
        ring_in.append(bm.verts.new((c * (r - width / 2), s * (r - width / 2), z)))
        ring_out.append(bm.verts.new((c * (r + width / 2), s * (r + width / 2), z)))
    cnt = len(ring_in)
    for i in range(cnt if full else cnt - 1):
        j = (i + 1) % cnt
        bm.faces.new((ring_in[i], ring_out[i], ring_out[j], ring_in[j]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def band_mesh(name, r, height, seg=192):
    """얇은 원통 띠 (기울어진 내부 링용)"""
    bm = bmesh.new()
    bot, top = [], []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        bot.append(bm.verts.new((r * math.cos(a), r * math.sin(a), -height / 2)))
        top.append(bm.verts.new((r * math.cos(a), r * math.sin(a), height / 2)))
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((bot[i], bot[j], top[j], top[i]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return bpy.data.objects.new(name, me)


def torus(name, R, r, maj=192, mn=8):
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, radius=1, segments=3)  # dummy for API compat
    bm.clear()
    rings = []
    for i in range(maj):
        u = 2 * math.pi * i / maj
        ring = []
        for k in range(mn):
            v = 2 * math.pi * k / mn
            x = (R + r * math.cos(v)) * math.cos(u)
            y = (R + r * math.cos(v)) * math.sin(u)
            ring.append(bm.verts.new((x, y, r * math.sin(v))))
        rings.append(ring)
    for i in range(maj):
        a, b = rings[i], rings[(i + 1) % maj]
        for k in range(mn):
            l = (k + 1) % mn
            bm.faces.new((a[k], b[k], b[l], a[l]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return bpy.data.objects.new(name, me)


# ------------------------------------------------------------------ 머티리얼
M_BRIGHT = emit_mat("ring_bright", AMBER, 9)
M_MAIN = emit_mat("ring_main", ORANGE, 6)
M_MID = emit_mat("ring_mid", ORANGE, 2.2)
M_DIM = emit_mat("ring_dim", ORANGE, 0.8)
M_FAINT = emit_mat("ring_faint", ORANGE, 0.3)
M_BLOCK_HI = emit_mat("block_hi", AMBER, 4)
M_BLOCK_LO = emit_mat("block_lo", ORANGE, 0.9)
M_BAND = emit_mat("band_glass", ORANGE, 1.0, alpha=0.25)
M_CORE = emit_mat("core", HOT, 30)
M_GRID = emit_mat("core_grid", AMBER, 2.5)

# ------------------------------------------------------------------ 1. 메인 외곽 링
main = link(arc_mesh("main_ring", 3.42, 0.055))
main.data.materials.append(M_MAIN)
glow = link(arc_mesh("main_ring_inner", 3.33, 0.02))
glow.data.materials.append(M_BRIGHT)

# ------------------------------------------------------------------ 2. 데이터 블록 링 (회전)
blocks_root = link(bpy.data.objects.new("blocks_root", None))
spin(blocks_root, 1)                     # 10초에 1바퀴

bm = bmesh.new()
rows = [(2.86, 3.02), (3.04, 3.14), (3.16, 3.24)]
cells = 144
# 클러스터 위치 (이미지처럼 덩어리진 데이터 블록)
clusters = [random.uniform(0, cells) for _ in range(13)]
face_mat = []
for ci in range(cells):
    near = min(min(abs(ci - c), cells - abs(ci - c)) for c in clusters)
    for (r0, r1) in rows:
        p = 0.85 if near < 2.5 else 0.12
        if random.random() > p:
            continue
        sub = random.choice([1, 2, 3])
        a0 = 2 * math.pi * ci / cells
        a1 = 2 * math.pi * (ci + 0.8) / cells
        hh = (r1 - r0) / sub
        for s in range(sub):
            ra, rb = r0 + s * hh + 0.005, r0 + (s + 1) * hh - 0.005
            vs = [bm.verts.new((ra * math.cos(a0), ra * math.sin(a0), 0)),
                  bm.verts.new((rb * math.cos(a0), rb * math.sin(a0), 0)),
                  bm.verts.new((rb * math.cos(a1), rb * math.sin(a1), 0)),
                  bm.verts.new((ra * math.cos(a1), ra * math.sin(a1), 0))]
            bm.faces.new(vs)
            face_mat.append(0 if (near < 2.5 and random.random() < 0.7) else 1)
me = bpy.data.meshes.new("data_blocks")
bm.to_mesh(me)
bm.free()
me.materials.append(M_BLOCK_HI)
me.materials.append(M_BLOCK_LO)
for p, mi in zip(me.polygons, face_mat):
    p.material_index = mi
blocks = link(bpy.data.objects.new("data_blocks", me), blocks_root)

# 블록 링 안팎의 가는 선
for r, w, m in [(2.84, 0.012, M_MID), (3.27, 0.01, M_MID), (2.70, 0.02, M_DIM)]:
    o = link(arc_mesh(f"line_{r}", r, w), blocks_root)
    o.data.materials.append(m)

# ------------------------------------------------------------------ 3. 반대방향 회전 동심원 + 눈금
ticks_root = link(bpy.data.objects.new("ticks_root", None))
spin(ticks_root, -1)
for r, w, m, a0, a1 in [(2.35, 0.012, M_DIM, 0, 360), (2.05, 0.008, M_FAINT, 0, 360),
                         (2.52, 0.02, M_MID, 20, 140), (2.52, 0.02, M_MID, 200, 320),
                         (1.85, 0.01, M_DIM, 60, 170), (1.85, 0.01, M_DIM, 250, 330)]:
    o = link(arc_mesh(f"circ_{r}_{a0}", r, w, a0, a1), ticks_root)
    o.data.materials.append(m)
bm = bmesh.new()
for i in range(180):
    a = 2 * math.pi * i / 180
    L = 0.09 if i % 5 == 0 else 0.04
    r0 = 2.38
    d = Vector((math.cos(a), math.sin(a), 0))
    t = Vector((-math.sin(a), math.cos(a), 0)) * 0.004
    p0, p1 = d * r0, d * (r0 + L)
    bm.faces.new([bm.verts.new(p0 - t), bm.verts.new(p1 - t), bm.verts.new(p1 + t), bm.verts.new(p0 + t)])
me = bpy.data.meshes.new("ticks")
bm.to_mesh(me)
bm.free()
me.materials.append(M_DIM)
link(bpy.data.objects.new("ticks", me), ticks_root)

# ------------------------------------------------------------------ 4. 바깥 호(arc) 스우시
arcs_root = link(bpy.data.objects.new("arcs_root", None))
sway(arcs_root, 0.6)
for r, w, a0, a1, m in [(3.85, 0.018, 35, 75, M_MID), (3.85, 0.018, 215, 250, M_MID),
                         (4.05, 0.01, 95, 130, M_DIM), (4.05, 0.01, 275, 320, M_DIM),
                         (3.70, 0.012, 150, 175, M_DIM), (3.70, 0.012, 330, 355, M_DIM)]:
    o = link(arc_mesh(f"arc_{r}_{a0}", r, w, a0, a1), arcs_root)
    o.data.materials.append(m)

# ------------------------------------------------------------------ 5. 기울어진 3D 내부 링 (자이로스코프)
def gyro(name, R, h, tilt, yaw, turns, precess):
    piv = link(bpy.data.objects.new(name + "_pivot", None))
    piv.rotation_euler = (0, 0, yaw)
    spin(piv, precess, axis=2, phase=yaw)
    tilt_e = link(bpy.data.objects.new(name + "_tilt", None), piv)
    tilt_e.rotation_euler = tilt
    ring = link(bpy.data.objects.new(name, None), tilt_e)
    spin(ring, turns)
    b = link(band_mesh(name + "_band", R, h), ring)
    b.data.materials.append(M_BAND)
    for dz in (-h / 2, h / 2):
        e = link(torus(f"{name}_edge{dz:+.2f}", R, 0.012), ring)
        e.location.z = dz
        e.data.materials.append(M_BRIGHT)
    # 띠 위의 데이터 패턴
    bm = bmesh.new()
    for i in range(96):
        if random.random() < 0.45:
            continue
        a0 = 2 * math.pi * i / 96
        a1 = a0 + 2 * math.pi / 96 * 0.7
        z0 = random.uniform(-h / 2 + 0.01, 0)
        z1 = z0 + random.uniform(0.02, h / 2)
        rr = R * 1.003
        bm.faces.new([bm.verts.new((rr * math.cos(a0), rr * math.sin(a0), z0)),
                      bm.verts.new((rr * math.cos(a1), rr * math.sin(a1), z0)),
                      bm.verts.new((rr * math.cos(a1), rr * math.sin(a1), z1)),
                      bm.verts.new((rr * math.cos(a0), rr * math.sin(a0), z1))])
    me = bpy.data.meshes.new(name + "_data")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M_BLOCK_HI)
    link(bpy.data.objects.new(name + "_data", me), ring)

gyro("gyroA", 1.85, 0.18, (math.radians(50), math.radians(-14), 0), math.radians(40), 1, 1)
gyro("gyroB", 1.68, 0.11, (math.radians(56), math.radians(8), 0), math.radians(25), -1, -1)

# ------------------------------------------------------------------ 6. 코어 (지오데식 구 + 빛나는 핵)
grid = link(bpy.data.objects.new("core_grid_root", None))
spin(grid, 1, axis=2)
drive(grid, "rotation_euler", f"0.4*sin((frame-1)/{LOOP}*2*pi)", 0)
for rad, sub, th in [(1.15, 2, 0.006), (0.7, 1, 0.008)]:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=rad)
    s = bpy.context.active_object
    s.name = f"core_geo_{rad}"
    s.parent = grid
    wf = s.modifiers.new("wire", "WIREFRAME")
    wf.thickness = th
    s.data.materials.append(M_GRID)

bpy.ops.mesh.primitive_uv_sphere_add(radius=0.2, segments=32, ring_count=16)
core = bpy.context.active_object
core.name = "core"
core.parent = ROOT
core.data.materials.append(M_CORE)
drive(M_CORE.node_tree.nodes["Emission"].inputs["Strength"], "default_value",
      f"30 + 9*sin((frame-1)/{LOOP}*2*pi*4)")   # 2.5초 주기 맥동

lamp = bpy.data.lights.new("core_light", "POINT")
lamp.color = (1.0, 0.55, 0.2)
lamp.energy = 150
link(bpy.data.objects.new("core_light", lamp))

# ------------------------------------------------------------------ 7. 떠다니는 입자
dust_root = link(bpy.data.objects.new("dust_root", None))
sway(dust_root, 0.35)
M_DUST = emit_mat("dust", AMBER, 12)
bm = bmesh.new()
for _ in range(30):
    a = random.uniform(0, 2 * math.pi)
    r = random.uniform(3.6, 4.8)
    c = Vector((r * math.cos(a), r * math.sin(a), random.uniform(-0.3, 0.3)))
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=random.uniform(0.006, 0.018),
                               matrix=__import__("mathutils").Matrix.Translation(c))
me = bpy.data.meshes.new("dust")
bm.to_mesh(me)
bm.free()
me.materials.append(M_DUST)
link(bpy.data.objects.new("dust", me), dust_root)

# ------------------------------------------------------------------ 8. 에너지 연기 (배경 평면)
bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -1.5))
haze = bpy.context.active_object
haze.name = "haze"
haze.parent = ROOT
sway(haze, -0.5)
mh = bpy.data.materials.new("haze")
mh.use_nodes = True
nt = mh.node_tree
nt.nodes.clear()
out = nt.nodes.new("ShaderNodeOutputMaterial")
tc = nt.nodes.new("ShaderNodeTexCoord")
noise = nt.nodes.new("ShaderNodeTexNoise")
noise.inputs["Scale"].default_value = 2.2
noise.inputs["Detail"].default_value = 8
noise.inputs["Roughness"].default_value = 0.6
noise.inputs["Distortion"].default_value = 1.4
grad = nt.nodes.new("ShaderNodeTexGradient")
grad.gradient_type = "SPHERICAL"
mapn = nt.nodes.new("ShaderNodeMapping")
mapn.inputs["Scale"].default_value = (0.24, 0.24, 0.24)
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.55
ramp.color_ramp.elements[1].position = 0.85
mul = nt.nodes.new("ShaderNodeMath")
mul.operation = "MULTIPLY"
em = nt.nodes.new("ShaderNodeEmission")
em.inputs["Color"].default_value = ORANGE
em.inputs["Strength"].default_value = 0.4
nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
nt.links.new(tc.outputs["Object"], mapn.inputs["Vector"])
nt.links.new(mapn.outputs[0], grad.inputs["Vector"])
nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], mul.inputs[0])
nt.links.new(grad.outputs["Fac"], mul.inputs[1])
nt.links.new(mul.outputs[0], em.inputs["Strength"])
nt.links.new(em.outputs[0], out.inputs[0])
haze.data.materials.append(mh)

# ------------------------------------------------------------------ 카메라
cam_d = bpy.data.cameras.new("cam")
cam_d.lens = 50
cam = bpy.data.objects.new("cam", cam_d)
scn.collection.objects.link(cam)
cam.location = (0, 0, 27)
scn.camera = cam
ROOT.location = (0, 0, 0)

# ------------------------------------------------------------------ 컴포지터: 블룸/글로우
def setup_compositor():
    if hasattr(scn, "compositing_node_group"):            # Blender 5.x
        tree = bpy.data.node_groups.new("JARVIS_comp", "CompositorNodeTree")
        scn.compositing_node_group = tree
        tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        out = tree.nodes.new("NodeGroupOutput")
        out_in = out.inputs[0]
    else:                                                  # Blender 4.x
        scn.use_nodes = True
        tree = scn.node_tree
        tree.nodes.clear()
        out = tree.nodes.new("CompositorNodeComposite")
        out_in = out.inputs["Image"]
    rl = tree.nodes.new("CompositorNodeRLayers")

    def glare(kind, size_or_strength, thr):
        g = tree.nodes.new("CompositorNodeGlare")
        def setp(attr, sock, val):
            if hasattr(g, attr):
                try:
                    setattr(g, attr, val if not isinstance(val, tuple) else val[0]); return
                except Exception:
                    pass
            if sock in g.inputs:
                g.inputs[sock].default_value = val if not isinstance(val, tuple) else val[1]
        setp("glare_type", "Type", (kind.upper(), kind.replace("_", " ").title()))
        setp("quality", "Quality", ("HIGH", "High"))
        setp("threshold", "Threshold", thr)
        if "Size" in g.inputs:
            g.inputs["Size"].default_value = size_or_strength
        elif hasattr(g, "size"):
            g.size = 9
        if "Strength" in g.inputs:
            g.inputs["Strength"].default_value = 1.0
        return g

    g1 = glare("bloom", 0.7, 0.8)
    g2 = glare("fog_glow", 0.4, 2.5)
    tree.links.new(rl.outputs["Image"], g1.inputs["Image"])
    tree.links.new(g1.outputs["Image"], g2.inputs["Image"])
    tree.links.new(g2.outputs["Image"], out_in)

try:
    setup_compositor()
except Exception as e:
    print("Compositor setup skipped:", e)

scn.frame_set(1)

# ------------------------------------------------------------------ CLI 저장
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if "--save" in argv:
    bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath(argv[argv.index("--save") + 1]))
print("JARVIS scene built.")
