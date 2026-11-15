#!/usr/bin/env python3
"""Static sanity checks for the Panda Adventure Godot project.

This does NOT replace Godot. It catches the problems that broke earlier attempts
before the editor is even opened:
  * scenes pointing at files that do not exist
  * scenes using resource ids or parent nodes that are not defined
  * node_paths exports pointing at missing nodes
  * Godot 3 syntax/APIs that fail in Godot 4
  * mixed tab/space indentation in GDScript (a hard parse error in Godot)
  * duplicate script file names
  * unbalanced brackets in scripts and shaders

Usage:  python3 tools/validate_project.py [project_root]
Exit code 0 = no errors.
"""
import os
import re
import sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
errors, warnings = [], []


def res_to_path(res):
    return os.path.join(ROOT, res.replace("res://", "", 1))


def rel(p):
    return os.path.relpath(p, ROOT)


GODOT3_PATTERNS = [
    (r"^\s*export\s*(\(|var)", "Godot 3 'export' (use @export)"),
    (r"^\s*onready\s+var", "Godot 3 'onready' (use @onready)"),
    (r"\byield\s*\(", "Godot 3 'yield' (use await)"),
    (r"\bKinematicBody(2D)?\b", "Godot 3 KinematicBody (use CharacterBody3D/2D)"),
    (r"\.instance\(\)", "Godot 3 .instance() (use .instantiate())"),
    (r"\bPool(String|Int|Real|Vector2|Vector3|Color|Byte)Array\b", "Godot 3 Pool*Array (use Packed*Array)"),
    (r"\bdeg2rad\b|\brad2deg\b", "Godot 3 deg2rad/rad2deg (use deg_to_rad/rad_to_deg)"),
    (r"\brand_range\b", "Godot 3 rand_range (use randf_range)"),
    (r"\bmove_and_slide\s*\(\s*\w", "Godot 3 move_and_slide(velocity) signature"),
    (r"\bSpatial\b", "Godot 3 Spatial (use Node3D)"),
    (r"\bsetget\b", "Godot 3 setget (use property set/get)"),
    (r"\btool\s*$", "Godot 3 'tool' keyword (use @tool)"),
    (r"\.connect\(\s*\"[^\"]+\"\s*,\s*self", "Godot 3 connect(signal, self, method) form"),
]


def check_brackets(text, path):
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    in_str = None
    for i, ch in enumerate(text):
        if in_str:
            if ch == in_str and text[i - 1] != "\\":
                in_str = None
            continue
        if ch in "\"'":
            in_str = ch
        elif ch == "#" and path.endswith(".gd"):
            # skip comment to end of line
            j = text.find("\n", i)
            continue
        elif ch in "([{":
            stack.append(ch)
        elif ch in ")]}":
            if not stack or stack[-1] != pairs[ch]:
                errors.append(f"{rel(path)}: unbalanced '{ch}' near char {i}")
                return
            stack.pop()
    if stack:
        errors.append(f"{rel(path)}: unclosed '{stack[-1]}'")


def strip_gd_comments(text):
    out = []
    for line in text.splitlines():
        res, in_str = "", None
        for ch in line:
            if in_str:
                res += ch
                if ch == in_str:
                    in_str = None
            elif ch in "\"'":
                in_str = ch
                res += ch
            elif ch == "#":
                break
            else:
                res += ch
        out.append(res)
    return "\n".join(out)


def check_gdscript(path):
    text = open(path, encoding="utf-8").read()
    lines = text.splitlines()
    first = next((l for l in lines if l.strip() and not l.strip().startswith("#")), "")
    if not first.startswith(("extends", "class_name", "@tool")):
        warnings.append(f"{rel(path)}: first statement is not 'extends'/'class_name'")
    for n, line in enumerate(lines, 1):
        indent = line[: len(line) - len(line.lstrip())]
        if " " in indent and "\t" in indent:
            errors.append(f"{rel(path)}:{n}: mixed tabs and spaces in indentation")
        elif indent.startswith(" ") and line.strip():
            errors.append(f"{rel(path)}:{n}: space indentation (project uses tabs)")
        code = strip_gd_comments(line)
        for pat, msg in GODOT3_PATTERNS:
            if re.search(pat, code):
                errors.append(f"{rel(path)}:{n}: {msg}")
    for m in re.finditer(r'(?:preload|load)\("(res://[^"]+)"\)', text):
        if not os.path.exists(res_to_path(m.group(1))):
            errors.append(f"{rel(path)}: missing resource {m.group(1)}")
    check_brackets(strip_gd_comments(text), path)


def check_shader(path):
    text = open(path, encoding="utf-8").read()
    code = re.sub(r"//.*", "", text)
    if not re.search(r"^\s*shader_type\s+\w+;", code, re.M):
        errors.append(f"{rel(path)}: missing shader_type")
    check_brackets(code, path)
    for m in re.finditer(r"smoothstep\(\s*([\d.]+)\s*,\s*([\d.]+)", code):
        if float(m.group(1)) > float(m.group(2)):
            errors.append(f"{rel(path)}: smoothstep edge0 > edge1 (undefined behaviour on some GPUs)")


def check_scene(path):
    text = open(path, encoding="utf-8").read()
    if not re.match(r"\[gd_(scene|resource)[^\]]*format=3", text):
        errors.append(f"{rel(path)}: header is not Godot 4 format=3")
    ext_ids, sub_ids = set(), set()
    for m in re.finditer(r'\[ext_resource ([^\]]*)\]', text):
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        ext_ids.add(attrs.get("id"))
        if not os.path.exists(res_to_path(attrs.get("path", ""))):
            errors.append(f"{rel(path)}: ext_resource missing file {attrs.get('path')}")
    for m in re.finditer(r'\[sub_resource [^\]]*id="([^"]+)"', text):
        if m.group(1) in sub_ids:
            errors.append(f"{rel(path)}: duplicate sub_resource id {m.group(1)}")
        sub_ids.add(m.group(1))
    for m in re.finditer(r'ExtResource\("([^"]+)"\)', text):
        if m.group(1) not in ext_ids:
            errors.append(f"{rel(path)}: undefined ExtResource {m.group(1)}")
    for m in re.finditer(r'SubResource\("([^"]+)"\)', text):
        if m.group(1) not in sub_ids:
            errors.append(f"{rel(path)}: undefined SubResource {m.group(1)}")
    # node tree
    nodes = {}
    root_name = None
    for m in re.finditer(r'\[node ([^\]]*)\]((?:\n(?!\[).*)*)', text):
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', m.group(1)))
        name, parent = attrs.get("name"), attrs.get("parent")
        if parent is None:
            if root_name is not None:
                errors.append(f"{rel(path)}: more than one root node")
            root_name = name
            full = "."
        else:
            if parent != "." and parent not in nodes:
                errors.append(f"{rel(path)}: node '{name}' has unknown parent '{parent}'")
            full = name if parent == "." else f"{parent}/{name}"
        if full in nodes:
            errors.append(f"{rel(path)}: duplicate node path '{full}'")
        nodes[full] = m.group(2)
        np = re.search(r'node_paths=PackedStringArray\(([^)]*)\)', m.group(1))
        if np:
            for prop in re.findall(r'"([^"]+)"', np.group(1)):
                pm = re.search(rf'^{prop} = NodePath\("([^"]*)"\)', m.group(2), re.M)
                if not pm:
                    errors.append(f"{rel(path)}: node '{full}' declares node path '{prop}' without a value")
                    continue
                target = os.path.normpath(os.path.join(full if full != "." else "", pm.group(1))).replace("\\", "/")
                if target not in nodes and target != "." and target not in [k for k in nodes]:
                    # targets may be declared later in the file; re-check at the end
                    pending.append((path, full, prop, target))
    return nodes


pending = []
scene_nodes = {}
script_names = {}
for dirpath, dirnames, files in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in (".godot", ".git", ".github", "build")]
    for f in files:
        p = os.path.join(dirpath, f)
        if f.endswith(".gd"):
            check_gdscript(p)
            script_names.setdefault(f, []).append(rel(p))
        elif f.endswith(".gdshader"):
            check_shader(p)
        elif f.endswith((".tscn", ".tres")):
            scene_nodes[p] = check_scene(p)

for path, node, prop, target in pending:
    if target not in scene_nodes.get(path, {}):
        errors.append(f"{rel(path)}: '{node}.{prop}' points to missing node '{target}'")

for name, paths in script_names.items():
    if len(paths) > 1:
        errors.append(f"duplicate script name {name}: {paths}")

proj = os.path.join(ROOT, "project.godot")
if not os.path.exists(proj):
    errors.append("project.godot missing")
else:
    ptext = open(proj, encoding="utf-8").read()
    if "config_version=5" not in ptext:
        errors.append("project.godot: config_version is not 5 (Godot 4)")
    for key in ("run/main_scene", "config/icon"):
        m = re.search(rf'{key}="([^"]+)"', ptext)
        if not m:
            errors.append(f"project.godot: {key} not set")
        elif not os.path.exists(res_to_path(m.group(1))):
            errors.append(f"project.godot: {key} points to missing {m.group(1)}")

counts = {k: sum(1 for d, _, fs in os.walk(ROOT) for f in fs if f.endswith(k) and "/.godot" not in d)
          for k in (".gd", ".tscn", ".gdshader", ".png")}
print(f"Checked: {counts['.gd']} scripts, {counts['.tscn']} scenes, {counts['.gdshader']} shaders, {counts['.png']} images")
for w in warnings:
    print("WARNING:", w)
for e in errors:
    print("ERROR:", e)
print("RESULT:", "PASS" if not errors else f"FAIL ({len(errors)} errors)")
sys.exit(1 if errors else 0)
