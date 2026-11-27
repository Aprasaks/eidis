"""
JARVIS 코어 분해 (Dissolve) — 코어가 조각나 금빛 불티와 함께 뒤로 날아가는 1회 연출.
코어 루프 영상의 1프레임과 똑같은 상태에서 시작 → 코어 루프가 한 바퀴 끝날 때 이어 틀면 끊김 없음.
역재생하면 '조립(부팅)' 연출.

  blender -b --factory-startup -P jarvis_dissolve.py -- --out dissolve.blend
"""
import bpy, bmesh, math, random, os, sys, runpy

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else os.getcwd()
_argv = sys.argv[:]
sys.argv = [a for a in sys.argv if a not in ("--out",)]       # 코어 스크립트의 --save 처리 회피
runpy.run_path(os.path.join(HERE, "jarvis_hologram.py"), run_name="__main__")
sys.argv = _argv

START, SPAN = 10, 60           # 분해 시작 프레임, 진행 길이 (70프레임에 모든 조각 안착)
DISSOLVE_END = 95              # 1~95: 분해 영상 (4초)
FLOAT = 192                    # 96~287: 배경에 떠다니는 잔해 루프 (8초, 심리스)
LENGTH = DISSOLVE_END + FLOAT
scn = bpy.context.scene
scn.frame_start, scn.frame_end = 1, LENGTH
random.seed(11)

try:                           # 날아가는 조각에 잔상(모션 블러)
    scn.render.use_motion_blur = True
    scn.render.motion_blur_shutter = 0.9
except Exception:
    pass


# ------------------------------------------------------------------ Shatter Geometry Nodes
def build_shatter():
    ng = bpy.data.node_groups.new("Shatter", "GeometryNodeTree")
    I = ng.interface
    I.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    I.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    for name, val in [("Progress", 0.0), ("Motion", 1.0), ("Distance", 3.0),
                      ("Back", 14.0), ("Appear", 0.0), ("Flare", 2.5),
                      ("Residual", 0.3), ("Bob", 0.25)]:
        s = I.new_socket(name, in_out="INPUT", socket_type="NodeSocketFloat")
        s.default_value = val
    N, L = ng.nodes.new, ng.links.new
    gi, go = N("NodeGroupInput"), N("NodeGroupOutput")

    def m(op, a, b=None, c=None):
        n = N("ShaderNodeMath"); n.operation = op
        for i, v in enumerate((a, b, c)):
            if v is None: continue
            if isinstance(v, (int, float)): n.inputs[i].default_value = v
            else: L(v, n.inputs[i])
        return n.outputs[0]

    def vm(op, a, b=None, out=0):
        n = N("ShaderNodeVectorMath"); n.operation = op
        for i, v in enumerate((a, b)):
            if v is None: continue
            if isinstance(v, (tuple, list)): n.inputs[i].default_value = v
            elif isinstance(v, (int, float)): n.inputs["Scale"].default_value = v
            else: L(v, n.inputs[i])
        return n.outputs[out]

    def vscale(v, s):
        n = N("ShaderNodeVectorMath"); n.operation = "SCALE"
        L(v, n.inputs[0])
        if isinstance(s, (int, float)): n.inputs["Scale"].default_value = s
        else: L(s, n.inputs["Scale"])
        return n.outputs[0]

    split = N("GeometryNodeSplitEdges")
    L(gi.outputs["Geometry"], split.inputs[0])

    cap = N("GeometryNodeCaptureAttribute")
    cap.domain = "FACE"
    cap.capture_items.new("VECTOR", "center")
    cap.capture_items.new("INT", "fid")
    L(split.outputs[0], cap.inputs["Geometry"])
    L(N("GeometryNodeInputPosition").outputs[0], cap.inputs["center"])
    L(N("GeometryNodeInputIndex").outputs[0], cap.inputs["fid"])
    center, fid = cap.outputs["center"], cap.outputs["fid"]

    def rnd(seed, kind="FLOAT", lo=0.0, hi=1.0):
        r = N("FunctionNodeRandomValue"); r.data_type = kind
        L(fid, r.inputs["ID"]); r.inputs["Seed"].default_value = seed
        v = (lambda x: x) if kind == "FLOAT" else (lambda x: (x,) * 3)
        r.inputs["Min"].default_value, r.inputs["Max"].default_value = v(lo), v(hi)
        return r.outputs["Value"]

    r_delay, r_dist, r_spin = rnd(1), rnd(2), rnd(3)
    r_axis = rnd(4, "FLOAT_VECTOR", -1.0, 1.0)

    # 안쪽부터 먼저 터지고, 조각마다 랜덤 지연
    rad = vm("LENGTH", vm("MULTIPLY", center, (1, 1, 0)), out=1)
    delay = m("ADD", m("MULTIPLY", r_delay, 0.40), m("MULTIPLY", m("MINIMUM", m("DIVIDE", rad, 4.0), 1.0), 0.18))
    local = m("DIVIDE", m("SUBTRACT", gi.outputs["Progress"], delay), 0.42)
    local = m("MINIMUM", m("MAXIMUM", local, 0.0), 1.0)
    # 순간 폭발 → 감속 → 그 자리에 떠 있음 (ease-out)
    travel = m("SUBTRACT", 1.0, m("POWER", m("SUBTRACT", 1.0, local), 3.0))
    em_ = m("MULTIPLY", travel, gi.outputs["Motion"])
    # 부유용 시간 (FLOAT 프레임 주기 → 루프 심리스)
    w = m("MULTIPLY", N("GeometryNodeInputSceneTime").outputs["Frame"], 2 * math.pi / FLOAT)
    ph = N("ShaderNodeSeparateXYZ"); L(rnd(6, "FLOAT_VECTOR", 0.0, 2 * math.pi), ph.inputs[0])
    px, py, pz = ph.outputs[0], ph.outputs[1], ph.outputs[2]
    r_back = rnd(5)

    # 이동: 바깥쪽 + 화면 안쪽(-Z) + 약간의 랜덤
    outward = vm("NORMALIZE", vm("ADD", vm("MULTIPLY", center, (1, 1, 0)), (1e-4, 1e-4, 0)))
    dist = m("MULTIPLY", m("MULTIPLY", gi.outputs["Distance"], m("ADD", r_dist, 0.5)), em_)
    back = m("MULTIPLY", m("MULTIPLY", gi.outputs["Back"], m("ADD", r_back, 0.15)), em_)
    backv = N("ShaderNodeCombineXYZ"); L(m("MULTIPLY", back, -1.0), backv.inputs[2])
    offset = vm("ADD", vm("ADD", vscale(outward, dist), backv.outputs[0]),
                vscale(r_axis, m("MULTIPLY", dist, 0.5)))
    # 둥실둥실 떠다님
    bob = N("ShaderNodeCombineXYZ")
    L(m("SINE", m("ADD", w, px)), bob.inputs[0])
    L(m("COSINE", m("ADD", w, py)), bob.inputs[1])
    L(m("MULTIPLY", m("SINE", m("ADD", w, pz)), 0.6), bob.inputs[2])
    amp = m("MULTIPLY", m("MULTIPLY", gi.outputs["Bob"], em_), m("ADD", r_dist, 0.5))
    offset = vm("ADD", offset, vscale(bob.outputs[0], amp))

    # 회전 + 축소
    rel = vm("SUBTRACT", N("GeometryNodeInputPosition").outputs[0], center)
    rot = N("ShaderNodeVectorRotate"); rot.rotation_type = "AXIS_ANGLE"
    L(rel, rot.inputs["Vector"]); L(vm("NORMALIZE", r_axis), rot.inputs["Axis"])
    tumble = m("ADD", m("ADD", m("MULTIPLY", r_spin, 10.0), 2.0), m("MULTIPLY", m("SINE", m("ADD", w, px)), 0.8))
    L(m("MULTIPLY", em_, tumble), rot.inputs["Angle"])
    shrink = m("SUBTRACT", 1.0, m("MULTIPLY", em_, 0.15))
    newpos = vm("ADD", vm("ADD", center, vscale(rot.outputs[0], shrink)), offset)
    sp = N("GeometryNodeSetPosition")
    L(cap.outputs[0], sp.inputs["Geometry"]); L(newpos, sp.inputs["Position"])

    # 밝기: 떨어져 나가는 순간 달아올랐다가(flare) 사그라짐
    bump = m("SINE", m("MULTIPLY", m("MINIMUM", m("MULTIPLY", local, 2.5), 1.0), math.pi))
    flare = m("ADD", 1.0, m("MULTIPLY", bump, gi.outputs["Flare"]))
    res = gi.outputs["Residual"]
    tail = m("ADD", res, m("MULTIPLY", m("SUBTRACT", 1.0, res), m("POWER", m("SUBTRACT", 1.0, local), 1.6)))
    twinkle = m("ADD", 1.0, m("MULTIPLY", m("MULTIPLY", m("SINE", m("ADD", m("MULTIPLY", w, 3.0), pz)), 0.45), travel))
    tail = m("MULTIPLY", tail, twinkle)
    unreleased = m("LESS_THAN", local, 1e-4)
    gate = m("SUBTRACT", 1.0, m("MULTIPLY", gi.outputs["Appear"], unreleased))
    fade = m("MULTIPLY", m("MULTIPLY", flare, tail), gate)

    st = N("GeometryNodeStoreNamedAttribute")
    st.data_type = "FLOAT"; st.domain = "POINT"
    st.inputs["Name"].default_value = "fade"
    L(sp.outputs[0], st.inputs["Geometry"]); L(fade, st.inputs["Value"])
    L(st.outputs[0], go.inputs[0])
    return ng


SHATTER = build_shatter()
ids = {it.name: it.identifier for it in SHATTER.interface.items_tree if getattr(it, "in_out", "") == "INPUT"}
PROG = f"clamp((frame-{START})/{SPAN},0,1)"


def add_shatter(ob, **vals):
    mod = ob.modifiers.new("Shatter", "NODES")
    mod.node_group = SHATTER
    new_api = hasattr(mod, "properties") and hasattr(mod.properties, "inputs")   # Blender 5.2+
    for k, v in vals.items():
        if new_api:
            getattr(mod.properties.inputs, ids[k]).value = float(v)
        else:
            mod[ids[k]] = float(v)
    path = (f'modifiers["Shatter"].properties.inputs.{ids["Progress"]}.value' if new_api
            else f'modifiers["Shatter"]["{ids["Progress"]}"]')
    fc = ob.driver_add(path)
    fc.driver.type = "SCRIPTED"
    fc.driver.expression = PROG
    return mod


def fade_material(mat):
    """Emission 색에 'fade' 속성을 곱함 (조각별 밝기)"""
    nt = mat.node_tree
    em = next((n for n in nt.nodes if n.type == "EMISSION"), None)
    if em is None or em.inputs["Color"].is_linked:
        return
    attr = nt.nodes.new("ShaderNodeAttribute"); attr.attribute_name = "fade"
    mix = nt.nodes.new("ShaderNodeVectorMath"); mix.operation = "SCALE"
    mix.inputs[0].default_value = em.inputs["Color"].default_value[:3]
    nt.links.new(attr.outputs["Fac"], mix.inputs["Scale"])
    nt.links.new(mix.outputs[0], em.inputs["Color"])


core = bpy.data.objects["core"]
haze = bpy.data.objects["haze"]
for mat in bpy.data.materials:
    if mat.name != "core" and mat.use_nodes:
        fade_material(mat)

for ob in list(scn.objects):
    if ob.type != "MESH" or ob is core:
        continue
    if ob is haze:
        add_shatter(ob, Motion=0.0, Flare=0.6, Residual=0.2)
    elif ob.name.startswith("core_geo"):
        add_shatter(ob, Distance=4.0, Back=8.0, Flare=3.0, Residual=0.9)
    elif ob.name == "dust":
        add_shatter(ob, Distance=5.0, Back=10.0, Flare=1.0, Residual=1.0)
    else:
        add_shatter(ob, Distance=6.0, Back=12.0, Flare=2.5, Residual=0.75)

# ------------------------------------------------------------------ 금빛 불티 (분해 순간 생겨나 뒤로 흩날림)
bm = bmesh.new()
for _ in range(1400):
    r = random.choice([random.uniform(2.8, 3.45), random.uniform(1.3, 1.9), random.uniform(0.3, 3.6)])
    a = random.uniform(0, 2 * math.pi)
    c = (r * math.cos(a), r * math.sin(a), random.uniform(-0.2, 0.2))
    s = random.uniform(0.008, 0.022)
    v = [bm.verts.new((c[0] + dx * s, c[1] + dy * s, c[2])) for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    bm.faces.new(v)
me = bpy.data.meshes.new("sparks")
bm.to_mesh(me); bm.free()
spark_mat = bpy.data.materials.get("dust").copy()
spark_mat.name = "sparks"
spark_mat.node_tree.nodes["Emission"].inputs["Strength"].default_value = 22
me.materials.append(spark_mat)
sparks = bpy.data.objects.new("sparks", me)
scn.collection.objects.link(sparks)
sparks.parent = bpy.data.objects["JARVIS_root"]
add_shatter(sparks, Distance=8.0, Back=16.0, Appear=1.0, Flare=1.5, Residual=0.8, Bob=0.35)

# ------------------------------------------------------------------ 코어 섬광 → 작은 불씨
cs = bpy.data.materials["core"].node_tree.nodes["Emission"].inputs["Strength"]
cs.driver_remove("default_value")
fc = cs.driver_add("default_value")
fc.driver.type = "SCRIPTED"
# 2026-11-27: 분해 뒤 가운데 흰 점이 남지 않도록 핵을 완전히 끈다 (대시보드 배경용 잔해 루프)
fc.driver.expression = ("30*(1-clamp((frame-14)/56,0,1)) + 160*exp(-pow((frame-10)/3,2))"
                        " + 9*sin((frame-1)/240*2*pi*4)*(1-clamp((frame-1)/12,0,1))")

# ------------------------------------------------------------------ 링 회전을 분해 후 부드럽게 멈춤 (잔해 루프가 정확히 반복되도록)
WARP = f"(min(frame,{START})+{SPAN//2}*(1-pow(1-clamp((frame-{START})/{SPAN},0,1),2)))"
for ob in scn.objects:
    ad = ob.animation_data
    if not ad:
        continue
    for fc in ad.drivers:
        if fc.data_path == "rotation_euler":
            fc.driver.expression = fc.driver.expression.replace("frame", "@").replace("@", WARP)
lamp = bpy.data.lights["core_light"]
fc = lamp.driver_add("energy")
fc.driver.type = "SCRIPTED"
fc.driver.expression = "150*(1-clamp((frame-14)/56,0,1)) + 600*exp(-pow((frame-10)/3,2))"

scn.frame_set(1)
argv = _argv[_argv.index("--") + 1:] if "--" in _argv else []
if "--out" in argv:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(argv[argv.index("--out") + 1]))
print("Dissolve scene built.")
