namespace BundlePack.Core;

internal sealed class Crc32Calculator
{
    private static readonly uint[] Table = CreateTable();
    private uint _state = uint.MaxValue;

    public uint Value => ~_state;

    public void Append(ReadOnlySpan<byte> data)
    {
        foreach (var value in data)
        {
            _state = Table[(_state ^ value) & 0xff] ^ (_state >> 8);
        }
    }

    private static uint[] CreateTable()
    {
        const uint polynomial = 0xedb8_8320;
        var table = new uint[256];
        for (uint index = 0; index < table.Length; index++)
        {
            var value = index;
            for (var bit = 0; bit < 8; bit++)
            {
                value = (value & 1) == 0 ? value >> 1 : (value >> 1) ^ polynomial;
            }

            table[index] = value;
        }

        return table;
    }
}
