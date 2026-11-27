"""
JARVIS 코어 생성 (Form) — 설계도 선이 그어지듯 나타나고, 빛이 들어오며 금색 코어가 된다. 3초(72프레임).

- 코어 루프(jarvis_hologram.py)를 그대로 불러와 프레임 -71~0 을 렌더한다.
  마지막 프레임(0)은 루프 1프레임 바로 앞 상태라서, 이어서 루프 영상을 틀면 끊김이 없다.
- 1) reveal: 바깥 링부터 안쪽으로, 각 선이 한 바퀴 그어지듯 나타남 (옅은 청백색 설계도 선)
  2) ignite : 선 색이 청백색 → 금색으로, 밝기 18% → 100%, 핵·조명·연기가 함께 켜짐

  blender -b --factory-startup -P jarvis_form.py -- --out form.blend
"""
import bpy, math, os, sys, runpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
_argv = sys.argv[:]
sys.argv = [a for a in sys.argv if a not in ("--out",)]
runpy.run_path(os.path.join(HERE, "jarvis_hologram.py"), run_name="__main__")
sys.argv = _argv

scn = bpy.context.scene
F0, F1 = -71, 0
scn.frame_start, scn.frame_end = F0, F1
BLUEPRINT = (0.78, 0.86, 1.0, 1.0)

# ------------------------------------------------------------- 진행 값 (씬 속성 키프레임)
scn["form_reveal"] = 0.0
scn["form_ignite"] = 0.0
for frame, value in [(F0, 0.0), (-30, 1.45), (F1, 1.45)]:      # 선 그리기: 약 1.7초
    scn["form_reveal"] = value
    scn.keyframe_insert('["form_reveal"]', frame=frame)
for frame, value in [(F0, 0.0), (-40, 0.0), (-10, 1.0), (F1, 1.0)]:  # 점화: 약 1.25초
    scn["form_ignite"] = value
    scn.keyframe_insert('["form_ignite"]', frame=frame)


def scene_value(nt, prop):
    """씬 속성을 읽는 Value 노드 (드라이버)."""
    node = nt.nodes.new("ShaderNodeValue")
    fc = node.outputs[0].driver_add("default_value")
    d = fc.driver
    d.type = "AVERAGE"
    v = d.variables.new()
    v.type = "SINGLE_PROP"
    v.targets[0].id_type = "SCENE"
    v.targets[0].id = scn
    v.targets[0].data_path = f'["{prop}"]'
    return node


def math_node(nt, op, a=None, b=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for i, x in enumerate((a, b)):
        if x is None:
            continue
        if isinstance(x, (int, float)):
            n.inputs[i].default_value = x
        else:
            nt.links.new(x, n.inputs[i])
    return n


def make_formable(m, scale_strength=True):
    nt = m.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    if not out.inputs[0].links:
        return
    src = out.inputs[0].links[0].from_socket
    em = next((n for n in nt.nodes if n.type == "EMISSION"), None)
    reveal = scene_value(nt, "form_reveal")
    ignite = scene_value(nt, "form_ignite")

    if em is not None:
        # 색: 설계도 청백색 → 원래 금색
        if not em.inputs["Color"].links:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.inputs[6].default_value = BLUEPRINT
            mix.inputs[7].default_value = tuple(em.inputs["Color"].default_value)
            nt.links.new(ignite.outputs[0], mix.inputs[0])
            nt.links.new(mix.outputs[2], em.inputs["Color"])
        # 밝기: 18% → 100% (드라이버로 맥동하는 핵은 그대로 둠)
        strength = em.inputs["Strength"]
        if scale_strength and not strength.links and not (m.node_tree.animation_data and m.node_tree.animation_data.drivers):
            base = strength.default_value
            ramp = math_node(nt, "MULTIPLY_ADD", ignite.outputs[0], 0.94)
            ramp.inputs[2].default_value = 0.06   # 설계도 단계는 가는 선처럼 은은하게
            scaled = math_node(nt, "MULTIPLY", ramp.outputs[0], base)
            nt.links.new(scaled.outputs[0], strength)

    # 보이는 범위: 오브젝트 중심 기준 각도 < (reveal - delay) * 2.5
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Object"], sep.inputs[0])
    ang = math_node(nt, "ARCTAN2", sep.outputs["Y"], sep.outputs["X"])
    frac = math_node(nt, "MULTIPLY_ADD", ang.outputs[0], 1 / (2 * math.pi))
    frac.inputs[2].default_value = 0.5
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_type = "OBJECT"
    attr.attribute_name = "form_delay"
    local = math_node(nt, "SUBTRACT", reveal.outputs[0], attr.outputs["Fac"])
    local = math_node(nt, "MULTIPLY", local.outputs[0], 2.5, clamp=True)
    visible = math_node(nt, "LESS_THAN", frac.outputs[0], local.outputs[0])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix_s = nt.nodes.new("ShaderNodeMixShader")
    if m.name == "core":
        # 빛나는 핵은 선이 다 그려진 뒤 점화와 함께 켜진다
        both = math_node(nt, "MULTIPLY", visible.outputs[0], ignite.outputs[0])
        nt.links.new(both.outputs[0], mix_s.inputs[0])
    else:
        nt.links.new(visible.outputs[0], mix_s.inputs[0])
    nt.links.new(tr.outputs[0], mix_s.inputs[1])
    nt.links.new(src, mix_s.inputs[2])
    nt.links.new(mix_s.outputs[0], out.inputs[0])


# ------------------------------------------------------------- 오브젝트별 지연 (바깥 링 먼저)
scn.frame_set(1)
radii = {}
for ob in scn.objects:
    if ob.type != "MESH" or ob.name == "haze":
        continue
    mw = ob.matrix_world
    r = max(((mw @ Vector(c)).to_2d().length for c in ob.bound_box), default=0.0)
    radii[ob] = r
rmax = max(radii.values()) if radii else 1.0
for ob, r in radii.items():
    ob["form_delay"] = 0.45 * (1.0 - min(r / rmax, 1.0))

for m in bpy.data.materials:
    if m.name == "haze" or not m.use_nodes:
        continue
    make_formable(m)

# 연기(배경)는 점화와 함께 서서히
mh = bpy.data.materials.get("haze")
if mh:
    nt = mh.node_tree
    em = next(n for n in nt.nodes if n.type == "EMISSION")
    src = em.inputs["Strength"].links[0].from_socket
    ignite = scene_value(nt, "form_ignite")
    mul = math_node(nt, "MULTIPLY", src, ignite.outputs[0])
    nt.links.new(mul.outputs[0], em.inputs["Strength"])

# 핵 조명도 점화와 함께
lamp = bpy.data.lights.get("core_light")
if lamp:
    for frame, energy in [(F0, 0.0), (-40, 0.0), (-10, 150.0)]:
        lamp.energy = energy
        lamp.keyframe_insert("energy", frame=frame)

scn.frame_set(F0)
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if "--out" in argv:
    bpy.ops.wm.save_as_mainfile(filepath=bpy.path.abspath(argv[argv.index("--out") + 1]))
