"""Builds the 3D mannequins (assets/models/*.glb) used by Outfitly.

Each model holds a smooth body plus every garment shape as its own mesh and
material (top_short, top_long, top_jacket, pants_long, pants_short, skirt,
dress, shoes_low, shoes_boot, hair). The app shows/hides and colors them.

Run:  pip install numpy scikit-image trimesh fast-simplification
      python3 tool/make_mannequin.py
"""
import os
import sys

import numpy as np
import trimesh
from skimage import measure

try:
    import fast_simplification
except ImportError:  # optional
    fast_simplification = None

RES = 0.007  # grid step in meters


# ---------------------------------------------------------------- SDF helpers
def smin(a, b, k):
    h = np.clip(k - np.abs(a - b), 0, None) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smin_all(ds, k):
    out = ds[0]
    for d in ds[1:]:
        out = smin(out, d, k)
    return out


def ellipsoid(P, c, r):
    q = (P - np.array(c)) / np.array(r)
    k0 = np.linalg.norm(q, axis=-1)
    k1 = np.linalg.norm(q / np.array(r), axis=-1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def capsule(P, a, b, ra, rb):
    a = np.array(a)
    b = np.array(b)
    ba = b - a
    pa = P - a
    h = np.clip((pa @ ba) / max(float(ba @ ba), 1e-9), 0.0, 1.0)
    return np.linalg.norm(pa - h[..., None] * ba, axis=-1) - (ra + (rb - ra) * h)


def lerp(a, b, t):
    return [a[i] + (b[i] - a[i]) * t for i in range(3)]


def flare(P, y_top, y_bot, r_top, r_bot, depth_ratio=0.8):
    """Skirt-like elliptic cone between two heights."""
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    t = np.clip((y_top - y) / (y_top - y_bot), 0, 1)
    r = r_top + (r_bot - r_top) * t
    q = np.sqrt(x * x + (z / depth_ratio) ** 2) - r
    return np.maximum.reduce([q, y - y_top, y_bot - y])


# ---------------------------------------------------------------- body plans
def plan(kind):
    if kind == "female":
        H = 1.70
        return dict(H=H, kid=False, head=(0.078, 0.112, 0.094), shoulder=0.165, chest=(0.145, 0.12, 0.098),
                    waist=(0.115, 0.11, 0.085), pelvis=(0.168, 0.12, 0.112), breasts=True, limb=1.0, long_hair=True)
    if kind == "male":
        H = 1.80
        return dict(H=H, kid=False, head=(0.08, 0.114, 0.098), shoulder=0.195, chest=(0.178, 0.14, 0.112),
                    waist=(0.145, 0.12, 0.1), pelvis=(0.155, 0.11, 0.105), breasts=False, limb=1.15, long_hair=False)
    H = 1.30
    return dict(H=H, kid=True, head=(0.08, 0.105, 0.092), shoulder=0.125, chest=(0.12, 0.1, 0.085),
                waist=(0.112, 0.1, 0.08), pelvis=(0.122, 0.09, 0.085), breasts=False, limb=0.8, long_hair=False)


def landmarks(p):
    H = p["H"]
    f = (dict(chin=0.83, shoulder=0.775, chest=0.70, waist=0.60, pelvis=0.52, crotch=0.455, knee=0.27, ankle=0.055)
         if p["kid"] else
         dict(chin=0.87, shoulder=0.815, chest=0.745, waist=0.635, pelvis=0.545, crotch=0.48, knee=0.285, ankle=0.055))
    L = {k: v * H for k, v in f.items()}
    L["head_c"] = L["chin"] + p["head"][1] * 0.95
    sh = p["shoulder"]
    lm = p["limb"]
    L["sh"] = sh
    L["arm"] = {}
    for s in (-1, 1):
        shoulder = [s * (sh - 0.01), L["shoulder"] - 0.025, -0.005]
        elbow = [s * (sh + 0.08), L["waist"] + 0.03, -0.02]
        wrist = [s * (sh + 0.135), L["crotch"] + 0.05, 0.02]
        L["arm"][s] = (shoulder, elbow, wrist)
    L["leg"] = {}
    hipx = p["pelvis"][0] * 0.52
    for s in (-1, 1):
        hip = [s * hipx, L["crotch"] + 0.06, 0.0]
        knee = [s * (hipx + 0.005), L["knee"], 0.012]
        ankle = [s * (hipx + 0.008), L["ankle"] + 0.012, -0.005]
        L["leg"][s] = (hip, knee, ankle)
    L["r"] = dict(upper=0.046 * lm, elbow=0.036 * lm, wrist=0.027 * lm,
                  thigh=p["pelvis"][0] * 0.5, knee=0.05 * lm, ankle=0.033 * lm)
    return L


def body_parts(P, p, L, arm_t=1.0, leg_t=1.0, with_head=True, with_arms=True, with_legs=True, with_feet=True):
    """Distance fields of body parts. arm_t / leg_t cut limbs short (0..1 along the limb)."""
    r = L["r"]
    d = []
    if with_head:
        d.append(ellipsoid(P, [0, L["head_c"], 0.005], p["head"]))
        d.append(capsule(P, [0, L["chin"] - 0.01, -0.005], [0, L["shoulder"] - 0.02, -0.01], 0.05 * p["limb"] ** 0.5, 0.058 * p["limb"] ** 0.5))
    d.append(capsule(P, [-L["sh"] + 0.03, L["shoulder"] - 0.03, -0.01], [L["sh"] - 0.03, L["shoulder"] - 0.03, -0.01], 0.055, 0.055))
    d.append(ellipsoid(P, [0, L["chest"], 0], p["chest"]))
    d.append(ellipsoid(P, [0, L["waist"], 0], p["waist"]))
    d.append(ellipsoid(P, [0, L["pelvis"], -0.005], p["pelvis"]))
    if p["breasts"]:
        for s in (-1, 1):
            d.append(ellipsoid(P, [s * 0.062, L["chest"] - 0.03, 0.068], [0.06, 0.055, 0.05]))
    if with_arms:
        for s in (-1, 1):
            sh, el, wr = L["arm"][s]
            if arm_t <= 0.5:
                end = lerp(sh, el, arm_t * 2)
                d.append(capsule(P, sh, end, r["upper"], r["upper"] + (r["elbow"] - r["upper"]) * arm_t * 2))
            else:
                d.append(capsule(P, sh, el, r["upper"], r["elbow"]))
                t = (arm_t - 0.5) * 2
                end = lerp(el, wr, t)
                d.append(capsule(P, el, end, r["elbow"], r["elbow"] + (r["wrist"] - r["elbow"]) * t))
            if arm_t >= 1.0:
                d.append(ellipsoid(P, [wr[0] + s * 0.004, wr[1] - 0.07, wr[2] + 0.005], [0.024, 0.07, 0.045]))
    if with_legs:
        for s in (-1, 1):
            hip, kn, an = L["leg"][s]
            if leg_t <= 0.5:
                end = lerp(hip, kn, leg_t * 2)
                d.append(capsule(P, hip, end, r["thigh"], r["thigh"] + (r["knee"] - r["thigh"]) * leg_t * 2))
            else:
                d.append(capsule(P, hip, kn, r["thigh"], r["knee"]))
                t = (leg_t - 0.5) * 2
                end = lerp(kn, an, t)
                d.append(capsule(P, kn, end, r["knee"], r["knee"] + (r["ankle"] - r["knee"]) * t))
                # calf muscle
                if t > 0.4:
                    d.append(ellipsoid(P, [kn[0], L["knee"] - (L["knee"] - L["ankle"]) * 0.32, -0.018],
                                       [r["knee"] * 0.98, (L["knee"] - L["ankle"]) * 0.3, r["knee"] * 0.95]))
    if with_feet:
        for s in (-1, 1):
            an = L["leg"][s][2]
            d.append(ellipsoid(P, [an[0] + s * 0.004, 0.042, 0.045], [0.042, 0.044, 0.11 * (0.85 if p["kid"] else 1)]))
    return d


def slab(P, y_lo=None, y_hi=None):
    y = P[..., 1]
    out = np.full(y.shape, -1.0)
    if y_hi is not None:
        out = np.maximum(out, y - y_hi)
    if y_lo is not None:
        out = np.maximum(out, y_lo - y)
    return out


def neck_hole(P, L, r, y_from):
    x, y, z = P[..., 0], P[..., 1], P[..., 2]
    q = np.sqrt(x * x + ((z - 0.01) / 0.9) ** 2) - r
    return np.maximum(q, y_from - y)


# ---------------------------------------------------------------- build
def build(kind, out_path):
    p = plan(kind)
    L = landmarks(p)
    H = p["H"]
    xs = np.arange(-0.45, 0.45 + RES, RES)
    ys = np.arange(-0.02, H + 0.03, RES)
    zs = np.arange(-0.25, 0.27, RES)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    P = np.stack([X, Y, Z], axis=-1)
    k = 0.06 * (0.8 if p["kid"] else 1)

    fields = {}

    # Body (skin).
    fields["skin"] = smin_all(body_parts(P, p, L), k)

    # Hair.
    head = ellipsoid(P, [0, L["head_c"], 0.005], [p["head"][0] + 0.008, p["head"][1] + 0.008, p["head"][2] + 0.008])
    face_cut = np.maximum(0.02 - P[..., 2], P[..., 1] - (L["head_c"] + 0.03))  # keep the face clear
    hair = np.maximum(head, -face_cut)
    if p["long_hair"]:
        back = ellipsoid(P, [0, L["head_c"] - 0.12, -0.06], [0.1, 0.17, 0.06])
        hair = smin(hair, np.maximum(back, -face_cut), 0.03)
    fields["hair"] = hair

    skin = fields["skin"]
    X_ = np.abs(P[..., 0])

    def xlimit(lim):
        return X_ - lim

    def sleeves(arm_t, radius=0.14):
        ds = []
        for sd in (-1, 1):
            sh, el, wr = L["arm"][sd]
            start = [sh[0] * 0.4, sh[1] + 0.04, sh[2]]
            if arm_t <= 0.5:
                ds.append(capsule(P, start, lerp(sh, el, arm_t * 2), radius, radius))
            else:
                ds.append(capsule(P, start, el, radius, radius))
                ds.append(capsule(P, el, lerp(el, wr, (arm_t - 0.5) * 2), radius, radius))
        return np.minimum.reduce(ds)

    def garment(t, region, neck_r=None, extra=None):
        d = np.maximum(skin - t, region)
        if extra is not None:
            d = smin(d, extra, 0.03)
        if neck_r is not None:
            d = np.maximum(d, -neck_hole(P, L, neck_r, L["shoulder"] - 0.05))
        return d

    chest_lim = p["chest"][0] + 0.03
    hip_lim = p["pelvis"][0] + 0.035
    neck_r = 0.07 if not p["kid"] else 0.06
    top_hi = L["shoulder"] + 0.07

    def top_region(lo, arm_t):
        # wider near the shoulders so the shoulder caps are covered
        tt = np.clip((P[..., 1] - L["chest"]) / (L["shoulder"] - L["chest"]), 0, 1)
        lim = chest_lim + tt * (L["sh"] + 0.1 - chest_lim)
        torso = np.maximum(slab(P, lo, top_hi), X_ - lim)
        return np.maximum(np.minimum(torso, sleeves(arm_t)), slab(P, lo, top_hi))

    fields["top_short"] = garment(0.017, top_region(L["pelvis"] - 0.02, 0.36), neck_r)
    fields["top_long"] = garment(0.016, top_region(L["pelvis"] - 0.03, 0.95), neck_r)
    fields["top_jacket"] = garment(0.023, top_region(L["pelvis"] - 0.05, 0.97), neck_r + 0.012)

    def leg_region(lo, hi):
        return np.maximum(slab(P, lo, hi), xlimit(hip_lim))

    fields["pants_long"] = garment(0.009, leg_region(L["ankle"] + 0.05, L["waist"] + 0.015))
    fields["pants_short"] = garment(0.011, leg_region(L["knee"] + 0.07, L["waist"] + 0.015))
    skirt_cone = flare(P, L["waist"], L["knee"] + 0.02, p["pelvis"][0] * 0.95, p["pelvis"][0] * 1.4)
    fields["skirt"] = garment(0.01, leg_region(L["crotch"] - 0.02, L["waist"] + 0.015), extra=skirt_cone)
    dress_cone = flare(P, L["waist"], L["knee"] - 0.02, p["pelvis"][0] * 0.95, p["pelvis"][0] * 1.5)
    dress_body = np.maximum(slab(P, L["crotch"] - 0.02, top_hi - 0.01), xlimit(chest_lim - 0.005))
    fields["dress"] = garment(0.012, dress_body, neck_r + 0.018, extra=dress_cone)

    fields["shoes_low"] = garment(0.012, slab(P, -0.02, L["ankle"] + 0.025))
    boot_top = L["ankle"] + (L["knee"] - L["ankle"]) * 0.55
    fields["shoes_boot"] = garment(0.016, slab(P, -0.02, boot_top))

    colors = {
        "skin": (0.91, 0.73, 0.59, 1), "hair": (0.23, 0.16, 0.12, 1),
        "top_short": (0.86, 0.85, 0.83, 1), "top_long": (0.86, 0.85, 0.83, 1), "top_jacket": (0.3, 0.3, 0.32, 1),
        "pants_long": (0.75, 0.74, 0.72, 1), "pants_short": (0.75, 0.74, 0.72, 1), "skirt": (0.6, 0.6, 0.6, 1),
        "dress": (0.6, 0.6, 0.6, 1), "shoes_low": (0.95, 0.95, 0.95, 1), "shoes_boot": (0.3, 0.22, 0.16, 1),
    }
    targets = {"skin": 26000, "hair": 5000}
    smooth_iters = {"skin": 8, "hair": 8}
    scene = trimesh.Scene()
    for name, field in fields.items():
        verts, faces, normals, _ = measure.marching_cubes(field, level=0.0, spacing=(RES, RES, RES))
        verts = verts + np.array([xs[0], ys[0], zs[0]])
        mesh = trimesh.Trimesh(verts, faces[:, ::-1], process=True)
        # keep the largest pieces only (drop tiny specks)
        parts = mesh.split(only_watertight=False)
        parts = [m for m in parts if len(m.faces) > 200]
        mesh = trimesh.util.concatenate(parts) if parts else mesh
        target = targets.get(name, 12000)
        if fast_simplification is not None and len(mesh.faces) > target:
            v, f = fast_simplification.simplify(mesh.vertices.astype(np.float32), mesh.faces.astype(np.int32),
                                                target_reduction=1 - target / len(mesh.faces))
            mesh = trimesh.Trimesh(v, f, process=True)
        trimesh.smoothing.filter_taubin(mesh, iterations=smooth_iters.get(name, 3))
        if mesh.volume < 0:
            mesh.invert()
        rough = 0.75 if name != "hair" else 0.55
        mat = trimesh.visual.material.PBRMaterial(name=name, baseColorFactor=colors[name], metallicFactor=0.0,
                                                  roughnessFactor=rough, doubleSided=True)
        mesh.visual = trimesh.visual.TextureVisuals(material=mat)
        scene.add_geometry(mesh, node_name=name, geom_name=name)
        print(f"  {name}: {len(mesh.faces)} faces")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    scene.export(out_path)
    print(f"{out_path}: {os.path.getsize(out_path) / 1e6:.2f} MB")


if __name__ == "__main__":
    kinds = sys.argv[1:] or ["female", "male", "kid"]
    root = os.path.join(os.path.dirname(__file__), "..", "assets", "models")
    for kd in kinds:
        print(kd)
        build(kd, os.path.join(root, f"{kd}.glb"))
