import argparse, os, struct, json
from math import exp

def read_shape(path):
    with open(path, 'r') as f:
        parts = f.read().strip().split()
        return [int(x) for x in parts]

def read_quant(path):
    with open(path, 'r') as f:
        parts = f.read().strip().split()
        t = int(parts[0]); scale = float(parts[1]); zp = int(parts[2])
        return t, scale, zp

def read_bin(path, t, scale, zp):
    b = open(path, 'rb').read()
    if t == 1: # kTfLiteFloat32
        n = len(b) // 4
        return list(struct.unpack('<' + 'f'*n, b))
    elif t == 3: # kTfLiteUInt8
        arr = list(b)
        return [ (x - zp) * scale for x in arr ]
    elif t == 9: # kTfLiteInt8
        arr = list(struct.unpack('<' + 'b'*len(b), b))
        return [ (x - zp) * scale for x in arr ]
    else:
        n = len(b) // 4
        return list(struct.unpack('<' + 'f'*n, b))

def nms(boxes, iou_thr=0.5, max_keep=200):
    def iou(a, b):
        x0 = max(a[0], b[0]); y0 = max(a[1], b[1])
        x1 = min(a[2], b[2]); y1 = min(a[3], b[3])
        iw = max(0.0, x1 - x0); ih = max(0.0, y1 - y0)
        inter = iw * ih
        areaA = max(0.0, (a[2]-a[0])) * max(0.0, (a[3]-a[1]))
        areaB = max(0.0, (b[2]-b[0])) * max(0.0, (b[3]-b[1]))
        return inter / (areaA + areaB - inter + 1e-6)
    order = sorted(range(len(boxes)), key=lambda i: boxes[i][4], reverse=True)
    keep = []
    for i in order:
        sup = False
        for k in keep:
            if iou(boxes[i], boxes[k]) > iou_thr:
                sup = True
                break
        if not sup:
            keep.append(i)
        if len(keep) >= max_keep:
            break
    return [boxes[i] for i in keep]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output-dir', required=True)
    ap.add_argument('--image', required=True)
    ap.add_argument('--save', required=True)
    args = ap.parse_args()

    od = args.output_dir
    bins = []
    shapes = []
    quants = []
    i = 0
    while True:
        b = os.path.join(od, f'output_{i}.bin')
        s = os.path.join(od, f'output_{i}.shape.txt')
        q = os.path.join(od, f'output_{i}.quant.txt')
        if not os.path.exists(b):
            break
        if os.path.exists(q):
            t, scale, zp = read_quant(q)
        else:
            t, scale, zp = 1, 1.0, 0
        v = read_bin(b, t, scale, zp)
        bins.append(v)
        shapes.append(read_shape(s))
        quants.append((t, scale, zp))
        i += 1

    W = H = None
    import subprocess, tempfile
    bmp_path = tempfile.mktemp(suffix='.bmp')
    subprocess.run(['sips', '-s', 'format', 'bmp', args.image, '--out', bmp_path], check=True)
    with open(bmp_path, 'rb') as f:
        f.read(14); dib = f.read(40)
        W = dib[4] | (dib[5]<<8) | (dib[6]<<16) | (dib[7]<<24)
        H = dib[8] | (dib[9]<<8) | (dib[10]<<16) | (dib[11]<<24)

    boxes = []
    if len(shapes) >= 3:
        s0 = shapes[0]; s1 = shapes[1]; s2 = shapes[2]
        if len(s0) >= 2 and s0[-1] == 4:
            N = s0[-2]
            b0 = bins[0]; b1 = bins[1]; b2 = bins[2]
            for i in range(N):
                cx = b0[i*4+0]; cy = b0[i*4+1]; w = b0[i*4+2]; h = b0[i*4+3]
                sx = W if max(cx, cy, w, h) <= 1.0 else 1.0
                sy = H if max(cx, cy, w, h) <= 1.0 else 1.0
                x0 = (cx - 0.5*w) * sx; y0 = (cy - 0.5*h) * sy
                x1 = (cx + 0.5*w) * sx; y1 = (cy + 0.5*h) * sy
                obj = b1[i] if len(b1) > i else 0.0
                cls = int(round(b2[i])) if len(b2) > i else 0
                score = max(obj, 0.001)
                boxes.append([x0, y0, x1, y1, score, cls])
    elif len(shapes) >= 1 and len(shapes[0]) == 2 and shapes[0][1] in (6,85):
        N = shapes[0][0]
        b0 = bins[0]
        F = shapes[0][1]
        for i in range(N):
            base = i*F
            cx, cy, w, h = b0[base+0], b0[base+1], b0[base+2], b0[base+3]
            obj = 1.0
            if F>5:
                obj_v = b0[base+4]
                obj = 1.0/(1.0+exp(-obj_v))
            sx = W if max(cx, cy, w, h) <= 1.0 else 1.0
            sy = H if max(cx, cy, w, h) <= 1.0 else 1.0
            x0 = (cx - 0.5*w) * sx; y0 = (cy - 0.5*h) * sy
            x1 = (cx + 0.5*w) * sx; y1 = (cy + 0.5*h) * sy
            boxes.append([x0, y0, x1, y1, obj, 0])

    boxes = [b for b in boxes if b[4] >= 0.02]
    boxes = nms(boxes, 0.5, 200)
    out_boxes = os.path.join(od, 'boxes.txt')
    with open(out_boxes, 'w') as f:
        for b in boxes:
            f.write(f"{int(b[0])} {int(b[1])} {int(b[2])} {int(b[3])} {b[4]:.4f} {int(b[5])}\n")

    try:
        from PIL import Image, ImageDraw
        im = Image.open(args.image).convert('RGB')
        draw = ImageDraw.Draw(im)
        for b in boxes:
            draw.rectangle([b[0], b[1], b[2], b[3]], outline=(255,0,0), width=2)
        im.save(args.save)
    except Exception:
        pass

if __name__ == '__main__':
    main()
