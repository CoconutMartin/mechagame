import math
def r(v): return f"{round(v,5):g}"
def xf(pos=(0,0,0), rot=(0,0,0)):
    """rot = (pitch_x, yaw_y, roll_z) degrees, Godot YXZ order."""
    pitch, yaw, roll = rot
    def mul(A,B): return [[sum(A[i][k]*B[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    cy,sy=math.cos(math.radians(yaw)),math.sin(math.radians(yaw))
    cx,sx=math.cos(math.radians(pitch)),math.sin(math.radians(pitch))
    cz,sz=math.cos(math.radians(roll)),math.sin(math.radians(roll))
    Ry=[[cy,0,sy],[0,1,0],[-sy,0,cy]]
    Rx=[[1,0,0],[0,cx,-sx],[0,sx,cx]]
    Rz=[[cz,-sz,0],[sz,cz,0],[0,0,1]]
    M=mul(mul(Ry,Rx),Rz)
    return "Transform3D(" + ", ".join(r(M[i][j]) for i in range(3) for j in range(3)) + f", {r(pos[0])}, {r(pos[1])}, {r(pos[2])})"

class Builder:
    """Collects mesh sub_resources and MeshInstance3D nodes."""
    def __init__(self):
        self.meshes = {}   # key -> (id, text)
        self.nodes = []
    def mesh(self, kind, *p):
        key = (kind,) + tuple(p)
        if key not in self.meshes:
            mid = f"m{len(self.meshes)}"
            if kind == "box":
                body = f"size = Vector3({r(p[0])}, {r(p[1])}, {r(p[2])})"
            elif kind == "cyl":  # radius top, radius bottom, height (axis Y)
                body = f"top_radius = {r(p[0])}\nbottom_radius = {r(p[1])}\nheight = {r(p[2])}\nradial_segments = 16\nrings = 1"
            elif kind == "sphere":
                body = f"radius = {r(p[0])}\nheight = {r(p[0]*2)}\nradial_segments = 16\nrings = 8"
            elif kind == "prism":  # size x,y,z, left_to_right
                body = f"size = Vector3({r(p[0])}, {r(p[1])}, {r(p[2])})\nleft_to_right = {r(p[3])}"
            t = {"box":"BoxMesh","cyl":"CylinderMesh","sphere":"SphereMesh","prism":"PrismMesh"}[kind]
            self.meshes[key] = (mid, f'[sub_resource type="{t}" id="{mid}"]\n{body}\n')
        return self.meshes[key][0]
    def part(self, name, parent, mat, kind, params, pos=(0,0,0), rot=(0,0,0)):
        mid = self.mesh(kind, *params)
        self.nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]\ntransform = {xf(pos, rot)}\nmesh = SubResource("{mid}")\nsurface_material_override/0 = ExtResource("{mat}")\n')
    def sub_text(self):
        return "\n".join(t for _, t in self.meshes.values())
