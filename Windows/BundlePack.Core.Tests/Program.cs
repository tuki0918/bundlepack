using System.Text;
using BundlePack.Core;
using static TestSupport;

const string password = "BundlePack-Compatibility-2026!";
const string composedUnicodePassword = "Caf\u00e9-Compatibility-2026!";
const string decomposedUnicodePassword = "Cafe\u0301-Compatibility-2026!";

var options = ParseArguments(args);
var repositoryRoot = options.TryGetValue("repo", out var explicitRoot)
    ? Path.GetFullPath(explicitRoot)
    : FindRepositoryRoot(Environment.CurrentDirectory);
var fixturesDirectory = options.TryGetValue("fixtures", out var explicitFixtures)
    ? Path.GetFullPath(explicitFixtures)
    : Path.Combine(repositoryRoot, "Fixtures", "Compatibility", "macOS");
var formatExpectationsPath = options.TryGetValue("format-expectations", out var explicitExpectations)
    ? Path.GetFullPath(explicitExpectations)
    : Path.Combine(repositoryRoot, "Fixtures", "FormatV1.json");
var formatExpectations = FormatContractExpectations.LoadAndVerify(formatExpectationsPath);
var outputDirectory = options.TryGetValue("output", out var explicitOutput)
    ? Path.GetFullPath(explicitOutput)
    : null;
var defaultIconPath = Path.Combine(
    repositoryRoot,
    "Windows",
    "BundlePack.Windows",
    "Assets",
    "DefaultPackageIcon.png");

var temporaryRoot = Path.Combine(Path.GetTempPath(), $"BundlePack-Windows-Tests-{Guid.NewGuid():N}");
Directory.CreateDirectory(temporaryRoot);
try
{
    var inputRoot = Path.Combine(temporaryRoot, "input");
    var nested = Path.Combine(inputRoot, "nested");
    var emptyDirectory = Path.Combine(nested, "empty");
    Directory.CreateDirectory(nested);
    Directory.CreateDirectory(emptyDirectory);
    var helloPath = Path.Combine(inputRoot, "hello.txt");
    var dataPath = Path.Combine(nested, "data.bin");
    var zeroBytePath = Path.Combine(nested, "zero-byte.dat");
    await File.WriteAllTextAsync(helloPath, "Hello from BundlePack compatibility tests\n", Encoding.UTF8);
    await File.WriteAllBytesAsync(dataPath, [0, 1, 2, 3, 4, 5]);
    await File.WriteAllBytesAsync(zeroBytePath, []);

    var iconPng = await File.ReadAllBytesAsync(defaultIconPath);
    var unencryptedPath = Path.Combine(temporaryRoot, "windows-unencrypted.bundlepack");
    var encryptedPath = Path.Combine(temporaryRoot, "windows-encrypted.bundlepack");
    var unicodePasswordPath = Path.Combine(temporaryRoot, "windows-unicode-password.bundlepack");
    var inputs = new[] { helloPath, nested };

    await File.WriteAllTextAsync(unencryptedPath, "stale package data", Encoding.UTF8);

    var unsafeTitlePath = await ArchiveValidationScenarios.RunAsync(temporaryRoot, iconPng);

    var createProgressValues = new List<double>();
    using (var created = await BundlePackService.CreateAsync(new PackageCreationRequest(
        "Windows Compatibility",
        "1.0.0",
        "BundlePack Tests",
        "Created by the C# compatibility test.",
        inputs,
        iconPng,
        EncryptionEnabled: false,
        Password: string.Empty,
        DestinationPath: unencryptedPath),
        progress: new ImmediateProgress<BundlePackOperationProgress>(value =>
            createProgressValues.Add(value.FractionCompleted))))
    {
        Require(!created.IsEncrypted && created.IsUnlocked, "The unencrypted package did not reopen.");
        Require(created.Archive?.PayloadFiles.Count == 3, "The unencrypted package has the wrong file count.");
    }
    Require(createProgressValues.Count > 0 && createProgressValues[^1] == 1, "Create progress did not reach 100%.");
    Require(
        createProgressValues.Zip(createProgressValues.Skip(1)).All(pair => pair.First <= pair.Second),
        "Create progress moved backwards.");
    Require(
        !Directory.EnumerateFiles(temporaryRoot, ".windows-unencrypted.bundlepack.*.tmp").Any(),
        "A temporary unencrypted package was not removed.");

    var cancelledPath = Path.Combine(temporaryRoot, "cancelled.bundlepack");
    using (var cancellation = new CancellationTokenSource())
    {
        cancellation.Cancel();
        try
        {
            using var ignored = await BundlePackService.CreateAsync(new PackageCreationRequest(
                "Cancelled",
                "1.0",
                string.Empty,
                string.Empty,
                [helloPath],
                iconPng,
                EncryptionEnabled: false,
                Password: string.Empty,
                DestinationPath: cancelledPath), cancellation.Token);
            throw new InvalidOperationException("A pre-cancelled create operation completed.");
        }
        catch (OperationCanceledException)
        {
            // Expected.
        }
    }
    Require(!File.Exists(cancelledPath), "A cancelled create operation left a destination file.");

    var midCancellationInput = Path.Combine(temporaryRoot, "mid-cancellation-input.bin");
    var midCancellationBytes = new byte[2 * 1_024 * 1_024];
    Random.Shared.NextBytes(midCancellationBytes);
    await File.WriteAllBytesAsync(midCancellationInput, midCancellationBytes);
    var midCancelledPath = Path.Combine(temporaryRoot, "mid-cancelled.bundlepack");
    using (var cancellation = new CancellationTokenSource())
    {
        var sawCopyProgress = false;
        try
        {
            using var ignored = await BundlePackService.CreateAsync(new PackageCreationRequest(
                "Mid Cancelled",
                "1.0",
                string.Empty,
                string.Empty,
                [midCancellationInput],
                iconPng,
                EncryptionEnabled: false,
                Password: string.Empty,
                DestinationPath: midCancelledPath),
                cancellation.Token,
                new ImmediateProgress<BundlePackOperationProgress>(value =>
                {
                    if (value.Message == "Copying files…" && value.FractionCompleted > 0.05)
                    {
                        sawCopyProgress = true;
                        cancellation.Cancel();
                    }
                }));
            throw new InvalidOperationException("A create operation cancelled during copying completed.");
        }
        catch (OperationCanceledException)
        {
            // Expected.
        }
        Require(sawCopyProgress, "The mid-operation cancellation test did not reach file copying.");
    }
    Require(!File.Exists(midCancelledPath), "A create operation cancelled during copying left a destination file.");

    var sameNameFileParent = Path.Combine(temporaryRoot, "same-name-file");
    var sameNameFolderParent = Path.Combine(temporaryRoot, "same-name-folder");
    Directory.CreateDirectory(sameNameFileParent);
    Directory.CreateDirectory(sameNameFolderParent);
    var sameNameFile = Path.Combine(sameNameFileParent, "shared");
    var sameNameFolder = Path.Combine(sameNameFolderParent, "shared");
    await File.WriteAllTextAsync(sameNameFile, "file", Encoding.UTF8);
    Directory.CreateDirectory(sameNameFolder);
    await File.WriteAllTextAsync(Path.Combine(sameNameFolder, "inside.txt"), "folder child", Encoding.UTF8);
    var sameNamePath = Path.Combine(temporaryRoot, "same-name.bundlepack");
    using (var sameNamePackage = await BundlePackService.CreateAsync(new PackageCreationRequest(
        "Same Name",
        "1.0",
        string.Empty,
        string.Empty,
        [sameNameFile, sameNameFolder],
        iconPng,
        EncryptionEnabled: false,
        Password: string.Empty,
        DestinationPath: sameNamePath)))
    {
        var sameNameFiles = sameNamePackage.Archive?.PayloadFiles
            ?? throw new InvalidOperationException("The same-name package did not reopen.");
        Require(
            sameNameFiles.Any(file => file.Path == "shared")
                && sameNameFiles.Any(file => file.Path == "shared 2/inside.txt"),
            "A same-name file and folder were not preserved with unique output names.");
    }

    try
    {
        using var ignored = await BundlePackService.CreateAsync(new PackageCreationRequest(
            new string('a', BundlePackConstants.MaximumTitleBytes + 1),
            "1",
            string.Empty,
            string.Empty,
            [helloPath],
            iconPng,
            EncryptionEnabled: false,
            Password: string.Empty,
            DestinationPath: Path.Combine(temporaryRoot, "oversized-metadata.bundlepack")));
        throw new InvalidOperationException("Oversized package display metadata was accepted.");
    }
    catch (BundlePackException exception) when (exception.Error == BundlePackError.InvalidManifest)
    {
        // Expected: macOS and Windows enforce the same UTF-8 display-field limits.
    }

    using (var created = await BundlePackService.CreateAsync(new PackageCreationRequest(
        "Windows Compatibility",
        "1.0.0",
        "BundlePack Tests",
        "Created by the C# compatibility test.",
        inputs,
        iconPng,
        EncryptionEnabled: true,
        Password: password,
        DestinationPath: encryptedPath)))
    {
        Require(created.IsEncrypted && !created.IsUnlocked, "The encrypted package exposed its contents before unlock.");
    }

    using (var created = await BundlePackService.CreateAsync(new PackageCreationRequest(
        "Windows Unicode Password Compatibility",
        "1.0.0",
        "BundlePack Tests",
        "Created with a canonically composed Unicode password.",
        inputs,
        iconPng,
        EncryptionEnabled: true,
        Password: composedUnicodePassword,
        DestinationPath: unicodePasswordPath)))
    {
        Require(created.IsEncrypted && !created.IsUnlocked, "The Unicode-password package exposed its contents before unlock.");
    }

    using (var unicodeUnlocked = await BundlePackService.OpenAsync(unicodePasswordPath, decomposedUnicodePassword))
    {
        var unicodeArchive = unicodeUnlocked.Archive
            ?? throw new InvalidOperationException("A canonically equivalent Unicode password was rejected.");
        VerifyPayload(unicodeArchive);
    }

    var encryptedBytes = await File.ReadAllBytesAsync(encryptedPath);
    formatExpectations.VerifyEncryptedHeader(encryptedBytes);
    Require(encryptedBytes.AsSpan(0, 8).SequenceEqual("BPKENC01"u8), "The encrypted signature is missing.");
    Require(encryptedBytes.AsSpan().IndexOf("hello.txt"u8) < 0, "An encrypted file name is visible in plaintext.");
    Require(encryptedBytes.AsSpan().IndexOf("Hello from BundlePack"u8) < 0, "Encrypted file data is visible in plaintext.");

    using (var unlocked = await BundlePackService.OpenAsync(encryptedPath, password))
    {
        var archive = unlocked.Archive
            ?? throw new InvalidOperationException("The Windows package could not be unlocked.");
        VerifyPayload(archive);
        var extractionParent = Path.Combine(temporaryRoot, "extracted");
        var extractionProgressValues = new List<double>();
        var extracted = await BundlePackService.ExtractAsync(
            unlocked,
            extractionParent,
            progress: new ImmediateProgress<BundlePackOperationProgress>(value =>
                extractionProgressValues.Add(value.FractionCompleted)));
        Require(
            extractionProgressValues.Count > 0 && extractionProgressValues[^1] == 1,
            "Extraction progress did not reach 100%.");
        Require(File.Exists(Path.Combine(extracted, "hello.txt")), "The extracted text file is missing.");
        Require(File.Exists(Path.Combine(extracted, "nested", "data.bin")), "The extracted nested file is missing.");
        Require(Directory.Exists(Path.Combine(extracted, "nested", "empty")), "An empty directory was not preserved.");
        Require(new FileInfo(Path.Combine(extracted, "nested", "zero-byte.dat")).Length == 0, "A zero-byte file was not preserved.");
    }

    try
    {
        using var ignored = await BundlePackService.OpenAsync(encryptedPath, "This-Is-The-Wrong-Password");
        throw new InvalidOperationException("An incorrect password was accepted.");
    }
    catch (BundlePackException exception) when (exception.Error == BundlePackError.WrongPasswordOrTampered)
    {
        // Expected.
    }

    await VerifyMacFixturesAsync(fixturesDirectory, password, composedUnicodePassword);

    if (outputDirectory is not null)
    {
        Directory.CreateDirectory(outputDirectory);
        File.Copy(unencryptedPath, Path.Combine(outputDirectory, Path.GetFileName(unencryptedPath)), overwrite: true);
        File.Copy(encryptedPath, Path.Combine(outputDirectory, Path.GetFileName(encryptedPath)), overwrite: true);
        File.Copy(unicodePasswordPath, Path.Combine(outputDirectory, Path.GetFileName(unicodePasswordPath)), overwrite: true);
    }

    string reviewedSnapshotPath;
    using (var reviewed = await BundlePackService.OpenAsync(unencryptedPath))
    {
        reviewedSnapshotPath = reviewed.Archive?.Path
            ?? throw new InvalidOperationException("The reviewed unencrypted package has no private snapshot.");
        Require(File.Exists(reviewedSnapshotPath), "The private review snapshot was not created.");
        File.Copy(unsafeTitlePath, unencryptedPath, overwrite: true);
        var extractionParent = Path.Combine(temporaryRoot, "review-bound-output");
        var extracted = await BundlePackService.ExtractAsync(reviewed, extractionParent);
        Require(
            string.Equals(Path.GetFileName(extracted), "Windows Compatibility", StringComparison.Ordinal),
            "Extraction used a package that replaced the reviewed source path.");
        Require(
            File.Exists(Path.Combine(extracted, "hello.txt")),
            "The reviewed snapshot payload was not extracted.");
    }
    Require(!File.Exists(reviewedSnapshotPath), "The private review snapshot was not deleted on Dispose.");

    Console.WriteLine("PASS: Windows create/open/encrypt/decrypt/extract, bounded metadata, review snapshots, and macOS fixture compatibility");
}
finally
{
    try
    {
        Directory.Delete(temporaryRoot, recursive: true);
    }
    catch
    {
        // Best-effort test cleanup.
    }
}
