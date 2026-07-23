namespace BundlePack.Core;

public static class BundlePackConstants
{
    public const string FileExtension = ".bundlepack";
    public const string FormatIdentifier = "com.tuki0918.bundlepack";
    public const int FormatVersion = 1;
    public const int AnimatedFormatVersion = 2;

    public const string AnimationPath = "animation.gif";
    public const string AnimationMediaType = "image/gif";
    public const int MaximumAnimationCanvasDimension = 1_024;
    public const int MaximumAnimationFrames = 120;
    public const int MaximumAnimationTotalPixels = 100_000_000;

    public const int MinimumPasswordCharacters = 12;
    public const int Pbkdf2Iterations = 600_000;
    public const int PlaintextChunkSize = 4 * 1_024 * 1_024;

    public const int MaximumEntries = 9_999;
    public const long MaximumExpandedSize = 20L * 1_024 * 1_024 * 1_024;
    public const int MaximumMetadataSize = 16 * 1_024 * 1_024;
    public const long MaximumInputFileSize = uint.MaxValue - 1L;

    public const int MaximumTitleBytes = 256;
    public const int MaximumPackageVersionBytes = 64;
    public const int MaximumAuthorBytes = 256;
    public const int MaximumSummaryBytes = 4_096;
}
