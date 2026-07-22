using System.Buffers.Binary;
using System.Text;
using System.Text.Json;
using BundlePack.Core;
using static TestSupport;

internal sealed class FormatContractExpectations
{
    public string FormatIdentifier { get; init; } = string.Empty;
    public int ManifestVersion { get; init; }
    public int MinimumPasswordCharacters { get; init; }
    public ContainerExpectations Container { get; init; } = new();
    public LimitExpectations Limits { get; init; } = new();
    public DisplayMetadataExpectations DisplayMetadataBytes { get; init; } = new();

    public static FormatContractExpectations LoadAndVerify(string path)
    {
        var expectations = JsonSerializer.Deserialize<FormatContractExpectations>(
            File.ReadAllText(path),
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidOperationException($"The format expectations are invalid: {path}");

        Require(
            expectations.FormatIdentifier == BundlePackConstants.FormatIdentifier,
            "The C# format identifier differs from Fixtures/FormatV1.json.");
        Require(
            expectations.ManifestVersion == BundlePackConstants.FormatVersion,
            "The C# manifest version differs from Fixtures/FormatV1.json.");
        Require(
            expectations.MinimumPasswordCharacters == BundlePackConstants.MinimumPasswordCharacters,
            "The C# password minimum differs from Fixtures/FormatV1.json.");
        Require(
            expectations.Container.Pbkdf2Iterations == BundlePackConstants.Pbkdf2Iterations
                && expectations.Container.PlaintextChunkSize == BundlePackConstants.PlaintextChunkSize,
            "The C# encrypted-container constants differ from Fixtures/FormatV1.json.");
        Require(
            expectations.Limits.MaximumAcceptedEntries == BundlePackConstants.MaximumEntries
                && expectations.Limits.MaximumExpandedBytes == BundlePackConstants.MaximumExpandedSize
                && expectations.Limits.MaximumMetadataBytes == BundlePackConstants.MaximumMetadataSize
                && expectations.Limits.MaximumInputFileBytes == BundlePackConstants.MaximumInputFileSize,
            "The C# package limits differ from Fixtures/FormatV1.json.");
        Require(
            expectations.DisplayMetadataBytes.Title == BundlePackConstants.MaximumTitleBytes
                && expectations.DisplayMetadataBytes.PackageVersion
                    == BundlePackConstants.MaximumPackageVersionBytes
                && expectations.DisplayMetadataBytes.Author == BundlePackConstants.MaximumAuthorBytes
                && expectations.DisplayMetadataBytes.Summary == BundlePackConstants.MaximumSummaryBytes,
            "The C# display metadata limits differ from Fixtures/FormatV1.json.");

        return expectations;
    }

    public void VerifyEncryptedHeader(ReadOnlySpan<byte> data)
    {
        var magic = Encoding.ASCII.GetBytes(Container.Magic);
        Require(
            data.Length >= Container.FixedHeaderSize && data.StartsWith(magic),
            "The encrypted output does not use the expected v1 header.");
        Require(
            BinaryPrimitives.ReadUInt16LittleEndian(data.Slice(8, 2)) == Container.Version
                && BinaryPrimitives.ReadUInt16LittleEndian(data.Slice(10, 2)) == Container.Flags
                && BinaryPrimitives.ReadUInt32LittleEndian(data.Slice(12, 4)) == Container.Pbkdf2Iterations
                && BinaryPrimitives.ReadUInt32LittleEndian(data.Slice(16, 4)) == Container.PlaintextChunkSize,
            "The encrypted output header differs from Fixtures/FormatV1.json.");

        var iconSize = checked((int)BinaryPrimitives.ReadUInt32LittleEndian(data.Slice(32, 4)));
        ReadOnlySpan<byte> pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
        Require(
            iconSize >= pngSignature.Length
                && data.Length >= Container.FixedHeaderSize + iconSize
                && data.Slice(Container.FixedHeaderSize).StartsWith(pngSignature),
            "The encrypted output public icon does not begin after the expected fixed header.");
    }

    internal sealed class ContainerExpectations
    {
        public string Magic { get; init; } = string.Empty;
        public ushort Version { get; init; }
        public ushort Flags { get; init; }
        public int FixedHeaderSize { get; init; }
        public uint Pbkdf2Iterations { get; init; }
        public uint PlaintextChunkSize { get; init; }
    }

    internal sealed class LimitExpectations
    {
        public int MaximumAcceptedEntries { get; init; }
        public long MaximumExpandedBytes { get; init; }
        public int MaximumMetadataBytes { get; init; }
        public long MaximumInputFileBytes { get; init; }
    }

    internal sealed class DisplayMetadataExpectations
    {
        public int Title { get; init; }
        public int PackageVersion { get; init; }
        public int Author { get; init; }
        public int Summary { get; init; }
    }
}
