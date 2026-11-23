import bpy, math, random
from mathutils import Vector
from math import sin, cos, pi
random.seed(17)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for m in bpy.data.materials: bpy.data.materials.remove(m)

def material(name, color, metal=0, rough=.4, emission=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal; p.inputs['Roughness'].default_value=rough
    p.inputs['Emission Color'].default_value=(*color,1); p.inputs['Emission Strength'].default_value=emission
    return m
bronze=material('Dark brushed bronze',(0.15,.052,.009),.82,.3)
gold=material('Antique gold',(.55,.23,.025),.8,.25)
amber=material('Amber light',(1,.24,.018),.25,.33,3)
hot=material('Warm core light',(1,.43,.055),.1,.3,5)
glass=material('Dark copper panels',(.095,.033,.008),.7,.2,.06)

def pivot(name, tilt, turns):
    o=bpy.data.objects.new(name,None); bpy.context.collection.objects.link(o)
    o.rotation_mode='XYZ'; o.rotation_euler=tilt
    # Child pivot rotates around local Z, preserving the parent's tilt.
    spin=bpy.data.objects.new(name+' rotation',None); bpy.context.collection.objects.link(spin); spin.parent=o
    spin.rotation_euler.z=0; spin.keyframe_insert(data_path='rotation_euler',index=2,frame=1)
    spin.rotation_euler.z=2*pi*turns; spin.keyframe_insert(data_path='rotation_euler',index=2,frame=241)
    if spin.animation_data and spin.animation_data.action:
        try:
            for f in spin.animation_data.action.fcurves:
                for k in f.keyframe_points: k.interpolation='LINEAR'
                f.modifiers.new('CYCLES')
        except AttributeError:
            action=spin.animation_data.action
            for layer in action.layers:
                for strip in layer.strips:
                    for slot in action.slots:
                        bag=strip.channelbag(slot)
                        if bag:
                            for f in bag.fcurves:
                                for k in f.keyframe_points: k.interpolation='LINEAR'
                                f.modifiers.new('CYCLES')
    return spin

def arc(name,r,width,depth,start,sweep,mat,parent):
    n=max(5,int(abs(sweep)*26))
    verts=[]; faces=[]
    for i in range(n+1):
        a=start+sweep*i/n
        for z,rad in [(-depth/2,r-width/2),(-depth/2,r+width/2),(depth/2,r-width/2),(depth/2,r+width/2)]:
            verts.append((rad*cos(a),rad*sin(a),z))
    for i in range(n):
        j=4*i; k=j+4
        faces.extend([(j,k,k+1,j+1),(j+2,j+3,k+3,k+2),(j,j+2,k+2,k),(j+1,k+1,k+3,j+3)])
    faces += [(0,1,3,2),(4*n,4*n+2,4*n+3,4*n+1)]
    mesh=bpy.data.meshes.new(name); mesh.from_pydata(verts,[],faces); mesh.update()
    ob=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(ob); ob.parent=parent; ob.data.materials.append(mat)
    bevel=ob.modifiers.new('Machined edges','BEVEL'); bevel.width=.008; bevel.segments=2
    ob.modifiers.new('Normals','WEIGHTED_NORMAL')
    return ob

layers=[
 ('Outer gimbal',1.76,(.35,.60,.18),1),
 ('Second gimbal',1.48,(1.05,.15,.35),-1),
 ('Inner armature',1.18,(.35,-.55,.6),2),
 ('Core cage',.86,(1.1,.8,.1),-2)]
for idx,(name,r,tilt,turns) in enumerate(layers):
    p=pivot(name,tilt,turns)
    count=9 if idx<2 else 7
    for i in range(count):
        a=2*pi*i/count+.08*idx
        sweep=(2*pi/count)*(.68 if i%3 else .48)
        arc(name+' gold segment',r,.11 if i%3==0 else .055,.085,a,sweep,gold if i%3==0 else bronze,p)
        arc(name+' luminous inlay',r,.010,.092,a+.035,max(.04,sweep-.07),amber,p)
        if i%2==0:
            arc(name+' offset panel',r-.09,.075,.035,a+.09,sweep*.45,glass,p)
    for i in range(42):
        if i%7==0: continue
        a=2*pi*i/42
        arc(name+' calibration mark',r+.08,.040 if i%5==0 else .018,.035,a,.014,amber if i%5==0 else gold,p)
    for i in range(4):
        a=2*pi*i/4+.13
        arc(name+' reinforced clamp',r,.19,.12,a,.12,bronze,p)
        arc(name+' clamp light',r,.10,.125,a+.035,.04,hot,p)

# Angular internal mechanism with depth and an illuminated center.
p=pivot('Inner reactor',(.5,.4,.3),1)
for j in range(4):
    q=bpy.data.objects.new('Reactor bearing %02d'%j,None); bpy.context.collection.objects.link(q); q.parent=p
    q.rotation_euler=(j*pi/4,j*.38,0)
    for i in range(8):
        arc('Reactor bearing segment',.47+j*.06,.055,.055,i*pi/4,.45,gold if j%2 else bronze,q)
        arc('Reactor light strip',.47+j*.06,.009,.061,i*pi/4+.04,.36,hot,q)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3,radius=.22)
core=bpy.context.object; core.name='Dark reactor heart'; core.data.materials.append(bronze)
for j in range(4):
    q=bpy.data.objects.new('Core illuminated plane %02d'%j,None); bpy.context.collection.objects.link(q); q.parent=p
    q.rotation_euler=(j*pi/4,j*.7,0)
    for i in range(6):
        arc('Inner energy filament',.25+j*.018,.012,.018,i*pi/3,.60,amber,q)

world=bpy.context.scene.world or bpy.data.worlds.new('World')
bpy.context.scene.world=world; world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.001,.0012,.002,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.15

def area(name,loc,color,power,size):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.color=color; data.shape='DISK'; data.size=size
    obj=bpy.data.objects.new(name,data); bpy.context.collection.objects.link(obj); obj.location=loc
    obj.rotation_euler=(Vector((0,0,0))-obj.location).to_track_quat('-Z','Y').to_euler()
area('Warm key',(3,-4,5),(1,.53,.22),950,5)
area('Gold rim',(-4,2,2),(1,.32,.05),1200,3)
area('Soft fill',(0,3,-3),(1,.68,.3),650,4)
data=bpy.data.lights.new('Core bounce','POINT'); data.energy=30; data.color=(1,.27,.03)
obj=bpy.data.objects.new('Core bounce',data); bpy.context.collection.objects.link(obj)
camdata=bpy.data.cameras.new('Camera'); cam=bpy.data.objects.new('Camera',camdata); bpy.context.collection.objects.link(cam)
cam.location=(4.7,-8.7,4.0); cam.rotation_euler=(-cam.location).to_track_quat('-Z','Y').to_euler()
camdata.type='ORTHO'; camdata.ortho_scale=4.8; bpy.context.scene.camera=cam
scene=bpy.context.scene
scene.render.engine='CYCLES'; scene.cycles.samples=32
scene.render.resolution_x=900; scene.render.resolution_y=900; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False
scene.frame_start=1; scene.frame_end=240; scene.render.fps=30; scene.frame_set(1)
scene.view_settings.view_transform='AgX'
bpy.ops.wm.save_as_mainfile(filepath='/Users/demian/Documents/JARVIS-MAC-v38/blender_core/JARVIS_core_v01.blend')
scene.render.filepath='/Users/demian/Documents/JARVIS-MAC-v38/blender_core/JARVIS_core_v01.png'
bpy.ops.render.render(write_still=True)
