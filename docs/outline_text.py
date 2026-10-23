# SPDX-FileCopyrightText: 2026 Mert Torun
# SPDX-License-Identifier: MIT
"""Turn a palette-flattened SVG (a variant of docs/social_preview.svg, or a badge) into a self-contained SVG.

Usage: outline_text.py <flattened.svg> <out.svg> <mono-font-dir> <sans-font-dir> [<source>]

<source> names the file the input was made from, for the header of the output;
docs/social_preview.svg when it is not given.

An SVG loaded as an image (<img>, <picture>) cannot load fonts, so every <text>
element is replaced by glyph outlines: shaped with HarfBuzz (hb-shape, which
applies the fonts' kerning), drawn with fontTools, each glyph defined once in
<defs> and placed with <use>. The CSS custom properties are resolved to literal
values, so that no renderer has to support var(); rules that only styled text
are dropped with it. Everything else (the animation of the session included) is kept.

The fonts are JetBrains Mono NL for the monospace runs and Fira Sans for the
sans-serif ones, both under the SIL Open Font License 1.1, whose condition 5
exempts documents created with the fonts. The master names Apple's SF fonts,
whose licence does not permit outlining them into a published file.
"""

import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

SVG_NS = "http://www.w3.org/2000/svg"
XML_SPACE = "{http://www.w3.org/XML/1998/namespace}space"
ET.register_namespace("", SVG_NS)

# Font file per (family class, CSS font-weight). A weight not listed is an error,
# never a silent substitution.
MONO = "JetBrainsMonoNLNerdFontMono-{}.ttf"
SANS = "FiraSans-{}.otf"
WEIGHTS = {
    "mono": {"500": MONO.format("Medium"), "600": MONO.format("SemiBold"), "700": MONO.format("Bold")},
    "sans": {"600": SANS.format("SemiBold"), "700": SANS.format("Bold")},
}
INHERITED = ("font-family", "font-size", "font-weight", "letter-spacing", "fill", "fill-opacity", "text-anchor")
TEXT_ONLY = {"font-family", "font-size", "font-weight", "letter-spacing", "text-anchor"}


def die(msg):
    print(f"outline_text.py: {msg}", file=sys.stderr)
    sys.exit(2)


def q(tag):
    return "{" + SVG_NS + "}" + tag


def num(v):
    """Shortest decimal for v, two places at most."""
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def split_blocks(css):
    """Top-level (prelude, body) pairs of a style sheet, nested braces kept in body."""
    out, i = [], 0
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    while True:
        j = css.find("{", i)
        if j < 0:
            if css[i:].strip():
                die(f"trailing CSS outside a block: {css[i:].strip()[:40]!r}")
            return out
        depth, k = 1, j + 1
        while depth:
            if k >= len(css):
                die("unbalanced braces in <style>")
            depth += {"{": 1, "}": -1}.get(css[k], 0)
            k += 1
        out.append((css[i:j].strip(), css[j + 1:k - 1].strip()))
        i = k


def declarations(body):
    decl = {}
    for part in body.split(";"):
        if part.strip():
            name, _, value = part.partition(":")
            decl[name.strip()] = value.strip()
    return decl


def main():
    if len(sys.argv) not in (5, 6):
        die("usage: outline_text.py <flattened.svg> <out.svg> <mono-font-dir> <sans-font-dir> [<source>]")
    src, dst, mono_dir, sans_dir = sys.argv[1:5]
    source = sys.argv[5] if len(sys.argv) == 6 else "docs/social_preview.svg"
    font_dir = {"mono": mono_dir, "sans": sans_dir}
    tree = ET.parse(src)  # comments are dropped; the output gets its own header
    root = tree.getroot()
    style_el = root.find(q("style"))
    if style_el is None:
        die("no <style> element")

    # 1. Resolve the custom properties and parse the class rules.
    blocks = split_blocks(style_el.text or "")
    variables, rules, verbatim = {}, {}, []
    for prelude, body in blocks:
        if prelude == ":root":
            variables.update({k: v for k, v in declarations(body).items() if k.startswith("--")})
        elif prelude.startswith("@media (prefers-color-scheme"):
            die("the input still carries a colour-scheme media block; pass a flattened variant")
        elif prelude.startswith("@"):
            verbatim.append((prelude, body))
        elif all(re.fullmatch(r"\.[\w-]+", s.strip()) for s in prelude.split(",")):
            # A list of class selectors styles each class; a later rule wins, as in CSS.
            for selector in prelude.split(","):
                rules.setdefault(selector.strip()[1:], {}).update(declarations(body))
        else:
            die(f"unsupported selector {prelude!r}")

    def resolve(value):
        out = re.sub(r"var\((--[\w-]+)\)", lambda m: variables.get(m.group(1)) or die(f"undefined {m.group(1)}"), value)
        if "var(" in out:
            die(f"unresolved var() in {value!r}")
        return out

    rules = {c: {k: resolve(v) for k, v in d.items()} for c, d in rules.items()}
    verbatim = [(p, resolve(b)) for p, b in verbatim]
    for el in root.iter():
        for k, v in el.attrib.items():
            if "var(" in v:
                el.set(k, resolve(v))

    parent = {c: p for p in root.iter() for c in p}

    def computed(el):
        chain = []
        while el is not None:
            chain.append(el)
            el = parent.get(el)
        style = {}
        for e in reversed(chain):
            for k in INHERITED:
                if k in e.attrib:
                    style[k] = e.get(k)
            for c in e.get("class", "").split():
                style.update({k: v for k, v in rules.get(c, {}).items() if k in INHERITED})
        return style

    # 2. Outline every <text>.
    fonts, glyph_ids, defs_paths = {}, {}, []

    def font_for(style):
        family = style.get("font-family", "")
        kind = "mono" if "monospace" in family else "sans"
        weight = style.get("font-weight", "400")
        name = WEIGHTS[kind].get(weight) or die(f"no {kind} font for weight {weight}")
        path = f"{font_dir[kind]}/{name}"
        if path not in fonts:
            try:
                fonts[path] = TTFont(path)
            except OSError as exc:
                die(f"cannot read font {path}: {exc}")
        return path

    def glyph_ref(path, gid):
        key = (path, gid)
        if key not in glyph_ids:
            font = fonts[path]
            gname = font.getGlyphOrder()[gid]
            pen = SVGPathPen(font.getGlyphSet(), ntos=lambda v: str(round(v)))
            font.getGlyphSet()[gname].draw(pen)
            d = pen.getCommands()
            glyph_ids[key] = None
            if d:
                gid_str = f"g{len(defs_paths)}"
                defs_paths.append((gid_str, d))
                glyph_ids[key] = gid_str
        return glyph_ids[key]

    def shape(path, text, letter_spacing):
        # CSS turns optional ligatures off where letter-spacing is set.
        features = ["--features=-liga,-clig"] if letter_spacing else []
        cmd = ["hb-shape", "--output-format=json", "--no-glyph-names", *features, path, text]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        except (OSError, subprocess.CalledProcessError) as exc:
            die(f"hb-shape failed on {text!r}: {exc}")
        return json.loads(res.stdout)

    texts = [t for t in root.iter(q("text"))]
    if not texts:
        die("no <text> element: nothing to outline")
    for text in texts:
        preserve = text.get(XML_SPACE) == "preserve"
        runs = []
        if text.text:
            runs.append((text.text, text))
        for child in text:
            if child.tag != q("tspan") or any(a in child.attrib for a in ("x", "y", "dx", "dy")):
                die("only positionless <tspan> children are supported")
            if child.text:
                runs.append((child.text, child))
            if child.tail:
                runs.append((child.tail, text))
        if not preserve:
            if len(runs) != 1:
                die("whitespace collapsing over several runs is not supported")
            runs = [(re.sub(r"\s+", " ", runs[0][0]).strip(), runs[0][1])]
        x0, y0 = float(text.get("x", "0")), float(text.get("y", "0"))
        pen_x, placed = 0.0, []
        for string, owner in runs:
            style = computed(owner)
            path = font_for(style)
            size = float(style.get("font-size", "16").removesuffix("px"))
            spacing = float(style.get("letter-spacing", "0").removesuffix("px"))
            upm = fonts[path]["head"].unitsPerEm
            scale = size / upm
            uses, run_x, last_cl = [], 0.0, None
            for g in shape(path, string, spacing):
                ref = glyph_ref(path, g["g"])
                if ref:
                    uses.append((ref, run_x + g["dx"], g["dy"]))
                run_x += g["ax"]
                if g["cl"] != last_cl:
                    last_cl = g["cl"]
                    run_x += spacing / scale  # letter-spacing follows every character, the last too
            placed.append((pen_x, scale, style, uses))
            pen_x += run_x * scale
        anchor = computed(text).get("text-anchor", "start")
        shift = {"start": 0.0, "middle": -pen_x / 2, "end": -pen_x}.get(anchor)
        if shift is None:
            die(f"unsupported text-anchor {anchor!r}")
        group = ET.Element(q("g"))
        for run_x0, scale, style, uses in placed:
            if not uses:
                continue
            g = ET.SubElement(group, q("g"), {"fill": style.get("fill", "#000")})
            if "fill-opacity" in style:
                g.set("fill-opacity", style["fill-opacity"])
            g.set("transform", f"translate({num(x0 + shift + run_x0)} {num(y0)}) scale({num(scale * 1000)}e-3 {num(-scale * 1000)}e-3)")
            for ref, ux, uy in uses:
                attrs = {"href": f"#{ref}"}
                if round(ux):
                    attrs["x"] = str(round(ux))
                if round(uy):
                    attrs["y"] = str(round(uy))  # the group's scale already points y up, as in the font
                ET.SubElement(g, q("use"), attrs)
        group = group[0] if len(group) == 1 else group
        holder = parent[text]
        holder[list(holder).index(text)] = group
        parent[group] = holder

    # 3. Drop the rules that styled text only, and the class names nothing styles any more.
    text_classes = {c for t in texts for e in t.iter() for c in e.get("class", "").split()}
    for c in list(rules):
        if c in text_classes or set(rules[c]) <= TEXT_ONLY:
            del rules[c]
    for el in root.iter():
        if "class" in el.attrib:
            kept = [c for c in el.get("class").split() if c in rules]
            if kept:
                el.set("class", " ".join(kept))
            else:
                del el.attrib["class"]
    for el in list(root.iter(q("g"))):
        # A wrapper left without attributes carries nothing: lift its children.
        if not el.attrib and el in parent:
            holder = parent[el]
            i = list(holder).index(el)
            holder[i:i + 1] = list(el)
            for c in el:
                parent[c] = holder

    css = [f".{c}{{{';'.join(f'{k}:{v}' for k, v in d.items())}}}" for c, d in rules.items()]
    for prelude, body in verbatim:
        inner = split_blocks(body) if "{" in body else None
        if inner:
            body = "".join(f"{p}{{{';'.join(f'{k}:{v}' for k, v in declarations(b).items())}}}" for p, b in inner)
        else:
            body = ";".join(f"{k}:{v}" for k, v in declarations(body).items())
        prelude = re.sub(r"\s+", " ", prelude)
        css.append(f"{prelude}{{{body}}}")
    style_el.text = "\n" + "\n".join(css) + "\n"

    defs = root.find(q("defs"))
    if defs is None:
        defs = ET.Element(q("defs"))
        root.insert(0, defs)
    for gid, d in defs_paths:
        ET.SubElement(defs, q("path"), {"id": gid, "d": d})

    title = root.find(q("title"))
    if title is None or not (title.text or "").strip():
        die("the master carries no <title>")
    root.remove(title)
    root.insert(0, title)

    ET.indent(tree, space="  ")
    names = sorted({fonts[p]["name"].getDebugName(4) + " " + fonts[p]["name"].getDebugName(5).split(";")[0] for p in fonts})
    header = (f"<!-- Generated by docs/render.sh from {source}; edit the source, not this file.\n"
              f"     Text outlined from {', '.join(names)}; SIL Open Font License 1.1. -->\n")
    body = ET.tostring(root, encoding="unicode")
    with open(dst, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(header + body + "\n")


if __name__ == "__main__":
    main()
