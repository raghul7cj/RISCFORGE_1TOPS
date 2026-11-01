from pathlib import Path


def load_word_mem(filepath):
    """
    Reads a 32-bit word-addressed .mem file.

    Input:
        @00000000
        00000097
        @00000001
        13408093

    Output:
        ['97','00','00','00',
         '93','80','40','13', ...]
    """

    filepath = Path(filepath)

    memory = []
    current_word = 0

    with filepath.open("r") as f:

        for line in f:
            line = line.strip()

            if not line or line.startswith("//"):
                continue

            if line.startswith("@"):
                current_word = int(line[1:], 16)

                byte_addr = current_word * 4

                while len(memory) < byte_addr:
                    memory.append("00")

            else:
                word = line.zfill(8).upper()

                # Convert 32-bit word into little-endian bytes
                bytes_le = [
                    word[6:8],
                    word[4:6],
                    word[2:4],
                    word[0:2],
                ]

                byte_addr = current_word * 4

                while len(memory) < byte_addr:
                    memory.append("00")

                for i, b in enumerate(bytes_le):
                    addr = byte_addr + i

                    if len(memory) == addr:
                        memory.append(b)
                    else:
                        memory[addr] = b

                current_word += 1

    return memory


def merge_mem(instr_file, data_file, output_file):

    instr = load_word_mem(instr_file)
    data = load_word_mem(data_file)

    merged = instr + data

    with open(output_file, "w") as f:
        for byte in merged:
            f.write(byte + "\n")

    print("=====================================")
    print("Conversion Complete")
    print("=====================================")
    print(f"Instruction image : {len(instr)} bytes")
    print(f"Data image        : {len(data)} bytes")
    print(f"Combined image    : {len(merged)} bytes")
    print(f"Output            : {output_file}")
    print("=====================================")


if __name__ == "__main__":

    base = Path(__file__).resolve().parent

    merge_mem(
        base / "ebreak_imem.mem",
        base / "ebreak_dmem.mem",
        base / "ebreak_combined.mem",
    )