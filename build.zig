const std = @import("std");
const zon = @import("build.zig.zon");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // My version stuff
    const options = b.addOptions();

    // Read version and name form build.zig.zon
    const name_str = @tagName(zon.name);
    const version = zon.version;

    options.addOption([]const u8, "name", name_str);
    options.addOption([]const u8, "version", version);

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("grab", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // business logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "grab",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "grab" is the name you will use in your source code to
                // import this module (e.g. `@import("grab")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "grab", .module = mod },
            },
        }),
    });

    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addOptions("build_options", options);

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const release_step = b.step("release", "Build release archives");

    const release_checks = ReleaseChecksStep.create(b, version);

    const release_targets = [_]ReleaseTarget{
        .{ .os_tag = .linux, .arch = .x86_64, .os_name = "linux", .arch_name = "amd64" },
        .{ .os_tag = .linux, .arch = .aarch64, .os_name = "linux", .arch_name = "arm64" },
        .{ .os_tag = .macos, .arch = .x86_64, .os_name = "darwin", .arch_name = "amd64" },
        .{ .os_tag = .macos, .arch = .aarch64, .os_name = "darwin", .arch_name = "arm64" },
    };

    for (release_targets) |release_target| {
        const resolved_target = b.resolveTargetQuery(.{
            .cpu_arch = release_target.arch,
            .os_tag = release_target.os_tag,
        });
        const release_exe = addReleaseExecutable(
            b,
            resolved_target,
            optimize,
            mod,
            clap,
            options,
        );

        const archive_name = b.fmt(
            "grab_{s}_{s}_{s}.tar.gz",
            .{ version, release_target.os_name, release_target.arch_name },
        );
        const dist_dir = "dist";
        const staging_dir = b.fmt("{s}/stage_{s}_{s}", .{
            dist_dir,
            release_target.os_name,
            release_target.arch_name,
        });

        // const clean_staging = b.addRemoveDirTree(b.path(staging_dir));
        const make_dist = b.addSystemCommand(&.{ "mkdir", "-p", dist_dir });
        const make_staging = b.addSystemCommand(&.{ "mkdir", "-p", staging_dir });
        // make_staging.step.dependOn(&clean_staging.step);

        const copy_bin = b.addSystemCommand(&.{"cp"});
        copy_bin.addFileArg(release_exe.getEmittedBin());
        copy_bin.addArg(staging_dir);

        const copy_docs = b.addSystemCommand(&.{ "cp", "README.md", "CHANGELOG.md", staging_dir });

        const tar_cmd = b.addSystemCommand(&.{
            "tar",
            "-czf",
            b.fmt("{s}/{s}", .{ dist_dir, archive_name }),
            "-C",
            staging_dir,
            ".",
        });

        // const clean_after = b.addRemoveDirTree(b.path(staging_dir));

        copy_bin.step.dependOn(&release_exe.step);
        copy_bin.step.dependOn(&make_staging.step);
        copy_bin.step.dependOn(&release_checks.step);
        copy_docs.step.dependOn(&make_staging.step);
        copy_docs.step.dependOn(&release_checks.step);
        tar_cmd.step.dependOn(&make_dist.step);
        tar_cmd.step.dependOn(&copy_bin.step);
        tar_cmd.step.dependOn(&copy_docs.step);
        tar_cmd.step.dependOn(&release_checks.step);
        // clean_after.step.dependOn(&tar_cmd.step);
        release_step.dependOn(&tar_cmd.step);
    }

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.

    // Set Up Changie Commands
    // WARNING: build() returns early here if changie deps are not fetched.
    // Do NOT add build steps after the changie block — they will be silently hidden.
    const changie_bin = get_changie_bin(b) orelse return;

    // Changie Add
    const changie_add = std.Build.Step.Run.create(b, "run changie");
    changie_add.addFileArg(changie_bin);
    changie_add.addArg("new");
    const changie_add_cmd = b.step("changie:add", "Add change log fragment");
    changie_add_cmd.dependOn(&changie_add.step);

    // Changie batch
    const changie_batch = std.Build.Step.Run.create(b, "run changie");
    changie_batch.addFileArg(changie_bin);
    changie_batch.addArg("batch");
    changie_batch.addArg(zon.version);
    const changie_batch_cmd = b.step("changie:batch", "Batch fragments for a release");
    changie_batch_cmd.dependOn(&changie_batch.step);

    // Changie merge
    const changie_merge = std.Build.Step.Run.create(b, "run changie");
    changie_merge.addFileArg(changie_bin);
    changie_merge.addArg("merge");
    const changie_merge_cmd = b.step("changie:merge", "Merge all changes into CHANGELOG.md");
    changie_merge_cmd.dependOn(&changie_merge.step);

    // Changie Version
    const changie_version = std.Build.Step.Run.create(b, "run changie");
    changie_version.addFileArg(changie_bin);
    changie_version.addArg("--version");
    const changie_version_cmd = b.step("changie:version", "Print the changie version");
    changie_version_cmd.dependOn(&changie_version.step);
}

const ReleaseTarget = struct {
    os_tag: std.Target.Os.Tag,
    arch: std.Target.Cpu.Arch,
    os_name: []const u8,
    arch_name: []const u8,
};

const ReleaseChecksStep = struct {
    step: std.Build.Step,
    version: []const u8,

    pub fn create(b: *std.Build, version: []const u8) *ReleaseChecksStep {
        const checks = b.allocator.create(ReleaseChecksStep) catch @panic("OOM");
        checks.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "release_checks",
                .owner = b,
                .makeFn = make,
            }),
            .version = b.dupe(version),
        };
        return checks;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = options;
        _ = step;
        // const checks: *ReleaseChecksStep = @fieldParentPtr("step", step);

        // var dir = try std.Io.Dir.cwd().openDir("changelog.d", io, .{ .iterate = true });
        // defer dir.close();
        // var iter = dir.iterate();
        // while (try iter.next()) |entry| {
        //     if (entry.kind != .file) continue;
        //     if (std.mem.eql(u8, entry.name, ".gitkeep")) continue;
        //     return step.fail("changelog.d contains fragment: {s}", .{entry.name});
        // }

        // const changelog = std.fs.cwd().readFileAlloc(step.owner.allocator, "CHANGELOG.md", 1024 * 1024) catch |err| {
        //     return step.fail("failed to read CHANGELOG.md: {s}", .{@errorName(err)});
        // };
        // defer step.owner.allocator.free(changelog);
        // if (std.mem.indexOf(u8, changelog, checks.version) == null) {
        //     return step.fail("CHANGELOG.md missing version {s}", .{checks.version});
        // }
    }
};

fn addReleaseExecutable(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    mod: *std.Build.Module,
    clap: *std.Build.Dependency,
    options: *std.Build.Step.Options,
) *std.Build.Step.Compile {
    _ = optimize;
    const release_optimize: std.builtin.OptimizeMode = .ReleaseSmall;
    const exe = b.addExecutable(.{
        .name = "grab",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = release_optimize,
            .imports = &.{
                .{ .name = "grab", .module = mod },
            },
        }),
    });

    exe.root_module.addImport("clap", clap.module("clap"));
    exe.root_module.addOptions("build_options", options);

    return exe;
}

fn get_changie_bin(b: *std.Build) ?std.Build.LazyPath {
    const host = b.graph.host.result;
    const name = switch (host.os.tag) {
        .linux => switch (host.cpu.arch) {
            .x86_64 => "changie_linux_amd64",
            .aarch64 => "changie_linux_arm64",
            else => return null,
        },
        .macos => switch (host.cpu.arch) {
            .x86_64 => "changie_darwin_amd64",
            .aarch64 => "changie_darwin_arm64",
            else => return null,
        },

        else => return null,
    };

    if (b.lazyDependency(name, .{})) |dep| {
        return dep.path("changie");
    } else {
        return null;
    }
}
