// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:math' as math;

import 'package:analyzer/src/generated/engine.dart';
import 'package:args/args.dart';
import 'package:linter/src/config.dart';
import 'package:linter/src/formatter.dart';
import 'package:linter/src/io.dart';
import 'package:linter/src/linter.dart';

void main(List<String> args) {
  runLinter(args, new LinterOptions());
}

const processFileFailedExitCode = 65;

const unableToProcessExitCode = 64;

String getRoot(List<String> paths) =>
    paths.length == 1 && new Directory(paths[0]).existsSync() ? paths[0] : null;

isLinterErrorCode(int code) =>
    code == unableToProcessExitCode || code == processFileFailedExitCode;

void printUsage(ArgParser parser, IOSink out, [String error]) {
  var message = "Lints Dart source files and pubspecs.";
  if (error != null) {
    message = error;
  }

  out.writeln('''$message
Usage: linter <file>
${parser.usage}
  
For more information, see https://github.com/dart-lang/linter
''');
}

void runLinter(List<String> args, LinterOptions initialLintOptions) {
  var parser = new ArgParser(allowTrailingOptions: true);

  parser
    ..addFlag("help",
        abbr: "h", negatable: false, help: "Shows usage information.")
    ..addFlag("stats",
        abbr: "s", negatable: false, help: "Show lint statistics.")
    ..addFlag('visit-transitive-closure',
        help: 'Visit the transitive closure of imported/exported libraries.')
    ..addFlag('quiet', abbr: 'q', help: "Don't show individual lint errors.")
    ..addFlag('machine',
        help: 'Print results in a format suitable for parsing.',
        defaultsTo: false,
        negatable: false)
    ..addOption('config', abbr: 'c', help: 'Use configuration from this file.')
    ..addOption('dart-sdk', help: 'Custom path to a Dart SDK.')
    ..addOption('package-root',
        abbr: 'p', help: 'Custom package root. (Discouraged.)');

  var options;
  try {
    options = parser.parse(args);
  } on FormatException catch (err) {
    printUsage(parser, errorSink, err.message);
    exitCode = unableToProcessExitCode;
    return;
  }

  if (options["help"]) {
    printUsage(parser, outSink);
    return;
  }

  if (options.rest.isEmpty) {
    printUsage(parser, errorSink,
        "Please provide at least one file or directory to lint.");
    exitCode = unableToProcessExitCode;
    return;
  }

  var lintOptions = initialLintOptions;

  var configFile = options["config"];
  if (configFile != null) {
    var config = new LintConfig.parse(readFile(configFile));
    lintOptions.configure(config);
  }

  var customSdk = options['dart-sdk'];
  if (customSdk != null) {
    lintOptions.dartSdkPath = customSdk;
  }

  var customPackageRoot = options['package-root'];
  if (customPackageRoot != null) {
    lintOptions.packageRootPath = customPackageRoot;
  }

  lintOptions.visitTransitiveClosure = options['visit-transitive-closure'];

  var linter = new DartLinter(lintOptions);

  List<File> filesToLint = [];
  for (var path in options.rest) {
    filesToLint.addAll(collectFiles(path));
  }

  try {
    List<AnalysisErrorInfo> errors = linter.lintFiles(filesToLint);

    if (errors.length > 0) {
      exitCode = _maxSeverity(errors);
    }

    var commonRoot = getRoot(options.rest);
    var stats = options['stats'];
    ReportFormatter reporter = new ReportFormatter(
        errors, lintOptions.filter, outSink,
        fileCount: linter.numSourcesAnalyzed,
        fileRoot: commonRoot,
        showStatistics: stats,
        machineOutput: options['machine'],
        quiet: options['quiet']);
    reporter.write();
  } catch (err, stack) {
    errorSink.writeln('''An error occurred while linting
  Please report it at: github.com/dart-lang/linter/issues
$err
$stack''');
  }
}

int _maxSeverity(List<AnalysisErrorInfo> errors) {
  int max = 0;
  errors.forEach((info) => info.errors.forEach(
      (error) => max = math.max(max, error.errorCode.errorSeverity.ordinal)));
  return max;
}
