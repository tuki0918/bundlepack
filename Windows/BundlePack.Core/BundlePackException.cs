namespace BundlePack.Core;

public enum BundlePackError
{
    NoInputFiles,
    InvalidIcon,
    PasswordTooShort,
    InvalidContainer,
    UnsupportedVersion,
    KeyDerivationFailed,
    WrongPasswordOrTampered,
    ContainerTooLarge,
    UnreadableArchive,
    NotZip,
    Zip64Unsupported,
    InvalidEntry,
    UnsafeEntry,
    EncryptedZipEntry,
    UnsupportedCompression,
    DuplicateEntry,
    MissingMetadata,
    InvalidManifest,
    UnsupportedFormat,
    ArchiveTooLarge,
    MissingPayload,
    WriteFailed
}

public sealed class BundlePackException : Exception
{
    public BundlePackException(BundlePackError error, string message)
        : base(message)
    {
        Error = error;
    }

    public BundlePackException(BundlePackError error, string message, Exception innerException)
        : base(message, innerException)
    {
        Error = error;
    }

    public BundlePackError Error { get; }
}
