import sys
import onnx

def main():
    if len(sys.argv) < 3:
        print("usage: convert_model_ir.py <input.onnx> <output.onnx>")
        sys.exit(1)
    inp = sys.argv[1]
    outp = sys.argv[2]
    m = onnx.load(inp)
    m.ir_version = 10
    onnx.save(m, outp)
    print(outp)

if __name__ == "__main__":
    main()
