import 'dart:io';

import 'package:args/args.dart';
import 'package:colorize/colorize.dart';

import 'analytics/analytics.dart';
import 'config_info/config_info.dart';
import 'create/create.dart';
import 'downloads/resource_manager.dart';
import 'generator/generator.dart';
import 'internal_tools/generate_pubspecs.dart';
import 'run/runner.dart';
import 'shared/environment.dart';
import 'util/command_line_tools.dart';
import 'util/print.dart';
import 'util/version.dart';

const cmdCreate = 'create';
const cmdGenerate = 'generate';
const cmdRun = 'run';
const cmdGeneratePubspecs = 'generate-pubspecs';
const cmdVersion = 'version';

final runModes = <String>['development', 'staging', 'production'];

final Analytics _analytics = Analytics();

void main(List<String> args) async {
  if (Platform.isWindows) {
    print(
        'WARNING! Windows is not officially supported yet. Things may or may not work as expected.');
    print('');
  }

  // Check that required tools are installed
  if (!await CommandLineTools.existsCommand('dart')) {
    print(
        'Failed to run serverpod. You need to have dart installed and in your \$PATH');
    return;
  }
  if (!await CommandLineTools.existsCommand('flutter')) {
    print(
        'Failed to run serverpod. You need to have flutter installed and in your \$PATH');
    return;
  }

  if (!loadEnvironmentVars()) {
    return;
  }

  // Make sure all necessary downloads are installed
  if (!resourceManager.isTemplatesInstalled) {
    try {
      await resourceManager.installTemplates();
    } catch (e) {
      print('Failed to download templates.');
    }

    if (!resourceManager.isTemplatesInstalled) {
      print(
          'Could not download the required resources for Serverpod. Make sure that you are connected to the internet and that you are using the latest version of Serverpod.');
      return;
    }
  }

  var parser = ArgParser();

  // "version" command
  var versionParser = ArgParser();
  parser.addCommand(cmdVersion, versionParser);

  // "create" command
  var createParser = ArgParser();
  createParser.addFlag('verbose',
      abbr: 'v', negatable: false, help: 'Output more detailed information');
  createParser.addFlag(
    'force',
    abbr: 'f',
    negatable: false,
    help:
        'Create the project even if there are issues that prevents if from running out of the box',
  );
  createParser.addOption(
    'template',
    abbr: 't',
    defaultsTo: 'server',
    allowed: <String>['server', 'module'],
    help:
        'Template to use when creating a new project, valid options are "server" or "module"',
  );
  parser.addCommand(cmdCreate, createParser);

  // "generate" command
  var generateParser = ArgParser();
  generateParser.addFlag('verbose',
      abbr: 'v', negatable: false, help: 'Output more detailed information');
  parser.addCommand(cmdGenerate, generateParser);

  // "run" command
  var runParser = ArgParser();
  runParser.addFlag('verbose',
      abbr: 'v', negatable: false, help: 'Output more detailed information');
  // TODO: Fix Docker management
  // runParser.addFlag('run-docker', negatable: true, defaultsTo: true);
  parser.addCommand(cmdRun, runParser);

  // "generate-pubspecs"
  var generatePubspecs = ArgParser();
  generatePubspecs.addOption('version', defaultsTo: 'X');
  generatePubspecs.addOption('mode',
      defaultsTo: 'development', allowed: ['development', 'production']);
  parser.addCommand(cmdGeneratePubspecs, generatePubspecs);

  var results = parser.parse(args);

  if (results.command != null) {
    _analytics.track(event: '${results.command?.name}');
    if (results.command!.name == cmdVersion) {
      printVersion();
      _analytics.cleanUp();
      return;
    }
    if (results.command!.name == cmdCreate) {
      var name = results.arguments.last;
      bool verbose = results.command!['verbose'];
      String template = results.command!['template'];
      bool force = results.command!['force'];
      if (name == 'server' || name == 'module' || name == 'create') {
        _printUsage(parser);
        _analytics.cleanUp();
        return;
      }
      var re = RegExp(r'^[a-z0-9_]+$');
      if (results.arguments.length > 1 && re.hasMatch(name)) {
        await performCreate(name, verbose, template, force);
        _analytics.cleanUp();
        return;
      }
    }
    if (results.command!.name == cmdGenerate) {
      await performGenerate(results.command!['verbose'], true);
      _analytics.cleanUp();
      return;
    }
    if (results.command!.name == cmdRun) {
      if (Platform.isWindows) {
        printwwln(
            'Sorry, `serverpod run` is not yet supported on Windows. You can still start your server by running:');
        stdout.writeln('  \$ docker-compose up --build --detach');
        stdout.writeln('  \$ dart .\\bin\\main.dart');
        printww('');
      } else {
        // TODO: Fix Docker management
        performRun(
          results.command!['verbose'],
        );
      }
      _analytics.cleanUp();
      return;
    }
    if (results.command!.name == cmdGeneratePubspecs) {
      if (results.command!['version'] == 'X') {
        print('--version is not specified');
        _analytics.cleanUp();
        return;
      }
      performGeneratePubspecs(
          results.command!['version'], results.command!['mode']);
      _analytics.cleanUp();
      return;
    }
  }

  _analytics.track(event: 'help');
  _printUsage(parser);
  _analytics.cleanUp();
}

void _printUsage(ArgParser parser) {
  print('${Colorize('Usage:')..bold()} serverpod <command> [arguments]\n');
  print('');
  print('${Colorize('COMMANDS')..bold()}');
  print('');
  _printCommandUsage(
    cmdVersion,
    'Prints the active version of the serverpod CLI util.',
  );
  _printCommandUsage(
    cmdCreate,
    'Creates a new Serverpod project, specify project name (must be lowercase with no special characters).',
    parser.commands[cmdCreate]!,
  );
  _printCommandUsage(
    cmdGenerate,
    'Generate code from yaml files for server and clients',
    parser.commands[cmdGenerate]!,
  );
  _printCommandUsage(
    cmdRun,
    'Run server in development mode. Code is generated continuously and server is hot reloaded when source files are edited.',
    parser.commands[cmdGenerate]!,
  );
}

void _printCommandUsage(String name, String descr,
    [ArgParser? parser, bool last = false]) {
  print('${Colorize('$name:')..bold()} $descr');
  if (parser != null) {
    print('');
    print(parser.usage);
    print('');
  }

  if (!last) {
    print('');
  }
}
