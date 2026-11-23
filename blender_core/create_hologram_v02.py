import bpy, math, random
from mathutils import Vector, Euler
from math import sin,cos,pi
random.seed(2217)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)

def mat(name,col,strength=0,metal=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*col,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF')
 p.inputs['Base Color'].default_value=(*col,1); p.inputs['Metallic'].default_value=metal
 p.inputs['Roughness'].default_value=.32
 p.inputs['Emission Color'].default_value=(*col,1); p.inputs['Emission Strength'].default_value=strength
 return m
dark=mat('01 · Deep bronze',(.12,.035,.004),.12,.75)
copper=mat('02 · Dim amber',(.75,.22,.014),.65,.35)
gold=mat('03 · Hologram gold',(1,.43,.035),2.3,.1)
flare=mat('04 · Hot gold',(1,.68,.16),6,.05)

def parent(name,tilt,turns):
 base=bpy.data.objects.new(name+' · axis',None); bpy.context.collection.objects.link(base); base.rotation_euler=tilt
 ob=bpy.data.objects.new(name+' · rotation',None); bpy.context.collection.objects.link(ob); ob.parent=base
 for f,angle in [(1,0),(481,turns*2*pi)]:
  ob.rotation_euler.z=angle; ob.keyframe_insert(data_path='rotation_euler',index=2,frame=f)
 action=ob.animation_data.action
 try: fs=action.fcurves
 except AttributeError: fs=action.layers[0].strips[0].channelbag(action.slots[0]).fcurves
 for fc in fs:
  for k in fc.keyframe_points: k.interpolation='LINEAR'
  fc.modifiers.new('CYCLES')
 return ob

def lines(name,paths,material,radius,par):
 curve=bpy.data.curves.new(name,'CURVE'); curve.dimensions='3D'; curve.resolution_u=1
 curve.bevel_depth=radius; curve.bevel_resolution=1; curve.resolution_u=1
 for pts in paths:
  spline=curve.splines.new('POLY'); spline.points.add(len(pts)-1)
  for point,co in zip(spline.points,pts): point.co=(*co,1)
 ob=bpy.data.objects.new(name,curve); bpy.context.collection.objects.link(ob); ob.parent=par; ob.data.materials.append(material)
 return ob

def arc(r,a,sweep,z=0,n=18):
 return [(r*cos(a+sweep*i/n),r*sin(a+sweep*i/n),z) for i in range(n+1)]

def panel(name,r,w,z,a,sweep,material,par):
 n=max(3,int(abs(sweep)*22)); v=[]; f=[]
 for i in range(n+1):
  t=a+sweep*i/n
  for rr in (r-w/2,r+w/2): v.append((rr*cos(t),rr*sin(t),z))
 for i in range(n): j=2*i; f.append((j,j+1,j+3,j+2))
 mesh=bpy.data.meshes.new(name); mesh.from_pydata(v,[],f); mesh.update()
 ob=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(ob); ob.parent=par; ob.data.materials.append(material)
 mod=ob.modifiers.new('subtle thickness','SOLIDIFY'); mod.thickness=.009

# Rings are broken, densely engraved 3D systems rotating on different tilted axes.
layers=[
 ('outer shell',1.72,(.30,.34,.17),1),
 ('outer meridian',1.62,(1.02,.27,.16),-1),
 ('left assembly',1.48,(.40,-.51,.35),1),
 ('tilted system',1.34,(.93,.67,-.19),-2),
 ('middle system',1.18,(.14,.36,.32),2),
 ('inner shell',.99,(.75,-.48,.10),-2),
 ('reactor chamber',.72,(.34,.36,.20),3)]
for idx,(name,r,tilt,turns) in enumerate(layers):
 p=parent(name,tilt,turns)
 dim=[]; bright=[]; hot=[]
 # Uneven arrays of fine concentric broken curves, spread through depth.
 for band in range(12):
  rr=r+(band-5.5)*.018
  z=random.uniform(-.075,.075)
  pieces=random.randint(7,13)
  for i in range(pieces):
   if random.random()<.24: continue
   a=2*pi*i/pieces+random.uniform(-.12,.12)
   sw=random.uniform(.11,.72)*(2*pi/pieces)
   (bright if random.random()<.18 else dim).append(arc(rr,a,sw,z,8))
 # Radial traces and right-angle circuit paths, asymmetrically distributed.
 for i in range(130 if idx<4 else 85):
  a=random.uniform(0,2*pi); rr=r+random.uniform(-.10,.11); z=random.uniform(-.09,.09)
  length=random.uniform(.025,.23)
  p1=(rr*cos(a),rr*sin(a),z); p2=((rr+length)*cos(a),(rr+length)*sin(a),z)
  da=random.choice([-1,1])*random.uniform(.012,.075)
  p3=((rr+length)*cos(a+da),(rr+length)*sin(a+da),z)
  (hot if random.random()<.055 else bright if random.random()<.3 else dim).append([p1,p2,p3])
 for i in range(15):
  a=random.uniform(0,2*pi); rr=r+random.uniform(-.06,.06)
  panel(name+' translucent plate',rr,random.uniform(.015,.045),random.uniform(-.09,.09),a,random.uniform(.045,.21),dark if i%3 else copper,p)
 lines(name+' gold filament',dim,copper,.0022,p)
 lines(name+' illuminated traces',bright,gold,.0020,p)
 lines(name+' highlights',hot,flare,.0028,p)

# Short broken latitude-like circuits in many planes add an irregular volumetric shell.
cloud=parent('distributed holographic structure',(.15,.12,.1),-1)
shellpaths=[[],[],[]]
for i in range(1150):
 axis=Vector((random.uniform(-1,1),random.uniform(-1,1),random.uniform(-1,1)))
 if axis.length<.1: continue
 axis.normalize(); helper=Vector((0,0,1)) if abs(axis.z)<.9 else Vector((0,1,0))
 u=axis.cross(helper).normalized(); v=axis.cross(u).normalized()
 r=random.uniform(.5,1.67); offset=random.uniform(-.42,.42); a=random.uniform(0,2*pi); sw=random.uniform(.015,.24)
 pts=[tuple(axis*offset + r*(u*cos(a+sw*j/5)+v*sin(a+sw*j/5))) for j in range(6)]
 shellpaths[2 if random.random()<.025 else 1 if random.random()<.23 else 0].append(pts)
for i,(m,w) in enumerate(((copper,.0015),(gold,.0018),(flare,.0024))): lines('floating fragmented circuits '+str(i),shellpaths[i],m,w,cloud)

# Central nested luminous rings, no solid white sphere.
center=parent('central energy aperture',(.6,.22,.2),3)
for k in range(7):
 ring=bpy.data.objects.new('aperture axis '+str(k),None); bpy.context.collection.objects.link(ring); ring.parent=center
 ring.rotation_euler=(random.uniform(-1,1),random.uniform(-1,1),0)
 paths=[]
 for j in range(12):
  a=j*2*pi/12+random.uniform(-.1,.1)
  paths.append(arc(.10+k*.032,a,random.uniform(.18,.46),0,8))
 lines('aperture segments',paths,flare if k<2 else gold,.004 if k<2 else .0025,ring)

world=bpy.data.worlds.new('Near black environment'); bpy.context.scene.world=world; world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.001,.001,.002,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.08
def area(name,loc,color,power,size):
 d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.color=color; d.shape='DISK'; d.size=size
 o=bpy.data.objects.new(name,d); bpy.context.collection.objects.link(o); o.location=loc; o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
area('Warm key',(3,-4,4),(1,.45,.08),360,4)
area('Rim',(-4,2,1),(1,.18,.02),450,3)
camera=bpy.data.objects.new('Camera',bpy.data.cameras.new('Camera')); bpy.context.collection.objects.link(camera)
camera.location=(3,-8,3); camera.rotation_euler=(-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'; camera.data.ortho_scale=4.5
s=bpy.context.scene; s.camera=camera
s.render.engine='CYCLES'; s.cycles.samples=32; s.cycles.use_denoising=True
s.render.resolution_x=1000; s.render.resolution_y=1000; s.render.resolution_percentage=100
s.render.image_settings.file_format='PNG'; s.frame_start=1; s.frame_end=480; s.render.fps=30; s.frame_set(1)
s.view_settings.view_transform='AgX'
# Blender 5 compositor uses a compositor node group.
group=bpy.data.node_groups.new('Amber bloom','CompositorNodeTree'); s.compositing_node_group=group
nodes=group.nodes; rl=nodes.new('CompositorNodeRLayers'); glare=nodes.new('CompositorNodeGlare'); glare.inputs['Type'].default_value='Fog Glow'; glare.inputs['Quality'].default_value='High'
out=nodes.new('NodeGroupOutput')
group.interface.new_socket(name='Image',in_out='OUTPUT',socket_type='NodeSocketColor')
group.links.new(rl.outputs['Image'],glare.inputs['Image']); group.links.new(glare.outputs['Image'],out.inputs['Image'])
bpy.ops.wm.save_as_mainfile(filepath='/Users/demian/Documents/JARVIS-MAC-v38/blender_core/JARVIS_hologram_v02.blend')
s.render.filepath='/Users/demian/Documents/JARVIS-MAC-v38/blender_core/JARVIS_hologram_v02.png'
bpy.ops.render.render(write_still=True)
