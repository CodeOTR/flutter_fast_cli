import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_util/cli_logging.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/cleanup/clear_unused_paas_files.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/cleanup/remove_feature_tags.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/cleanup/remove_injectable_environments.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/cleanup/remove_logo_color_scheme.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/cleanup/remove_run_configurations.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/cleanup/remove_subscription_feature.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/cleanup/update_pubspec_file.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/copy_template/load_template_folder.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/native_updates/remove_billing_dependency.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/native_updates/create_key_file.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/native_updates/fastlane_setup.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/copy_template/copy_template.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/native_updates/remove_shorebird_lanes.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/root_updates/create_root_files.dart';
import 'package:flutter_fast_cli/src/commands/create_app/steps/native_updates/update_android_build_gradle.dart';
import 'package:flutter_fast_cli/src/commands/strings.dart';
import 'package:flutter_fast_cli/src/commands/utils/utils.dart';

class CreateApp extends Command {
  @override
  String get description =>
      'Create a new Flutter app with all the bells and whistles.';

  @override
  String get name => 'app';

  @override
  ArgParser get argParser {
    return ArgParser()
      ..addOption('name', abbr: 'n', help: 'The name of the app to create.')
      ..addOption(
        'org',
        abbr: 'o',
        help: 'The organization to use for the app.',
        valueHelp: 'com.example',
        defaultsTo: 'com.example',
      )
      ..addFlag(
        'offline',
        abbr: 'f',
        help: 'Whether the app should be specifically for offline use.',
        defaultsTo: false,
      )
      ..addFlag(
        'subs',
        abbr: 's',
        help: 'Whether to include subscriptions in the app.',
        defaultsTo: true,
        negatable: true,
      )
      ..addFlag(
        'build',
        abbr: 'b',
        help: 'Whether to run the build_runner after the app has been created.',
        defaultsTo: true,
        negatable: true,
      )
      ..addFlag(
        'shorebird',
        abbr: 'r',
        help: 'Whether to include Shorebird lanes in Fastfiles.',
        defaultsTo: true,
        negatable: true,
      )
      ..addFlag(
        'logo-color-scheme',
        abbr: 'c',
        help: 'Whether to generate a ColorScheme from your logo.',
        defaultsTo: true,
        negatable: true,
      )
      ..addOption(
        'paas',
        abbr: 'p',
        help: 'The PaaS to use for the app. If left blank, all files will be '
            'included and you can use --dart-define to choose which one to use.',
        valueHelp: 'firebase',
        allowed: ['firebase', 'supabase', 'appwrite'],
      );
  }

  @override
  Future<void> run() async {
    final appName = argResults?['name'] as String?;
    final orgName = argResults?['org'] as String?;
    final offline = argResults?['offline'] as bool;
    final paas = argResults?['paas'] as String?;
    final subscriptions = argResults?['subs'] as bool;
    final build = (argResults?['build'] ?? true) as bool;
    final shorebird = argResults?['shorebird'] as bool;
    final logoColorScheme = argResults?['logo-color-scheme'] as bool;

    var logger = Logger.standard();

    if (appName == null || appName.isEmpty) {
      print('Please provide a name for your app.');
      return;
    }

    if (orgName == null || orgName.isEmpty) {
      print(
          'Please provide an organization name for your app (ex. com.example).');
      return;
    }

    var progress = logger.progress('Creating app $appName...');
    await Process.run(
        flutterPath, ['create', appName, '--empty', '--org', orgName]);
    progress.finish(showTiming: true);

    progress = logger.progress('Copying template...');
    String? path = await loadTemplateFolder(offline);

    if (path == null) {
      logger.stdout('Template path is null');
      return;
    }

    templatePath = path;
    await copyTemplate(templatePath, appName);
    progress.finish(showTiming: true);

    progress = logger.progress('Creating root files...');
    await createRootFiles(templatePath, appName);
    progress.finish(showTiming: true);

    progress = logger.progress('Updating native files...');
    await updateAndroidBuildGradle(appName, orgName);
    await fastlaneSetup(templatePath, appName);
    await createKeyFile();
    if (!shorebird) await removeShorebirdLanes();
    if (!subscriptions) removeBillingDependency(templatePath, appName);
    progress.finish(showTiming: true);

    progress = logger.progress('Performing cleanup...');
    if (paas != null) {
      await clearUnusedPaasFiles(paas);
      await updatePubspecFile(appName, paas);
      await removeInjectableEnvironments();
    }

    if (!subscriptions) {
      await removeSubscriptionFeature();
    }

    if (!logoColorScheme) {
      await removeLogoColorScheme();
    }

    await removeRunConfigurations();

    await removeFeatureTags();

    progress.finish(showTiming: true);

    progress = logger.progress('Running flutter pub get...');
    await Process.run(flutterPath, ['pub', 'get']);
    progress.finish(showTiming: true);

    if (build) {
      progress = logger.progress('Running build_runner...');
      await Process.run(flutterPath, [
        'pub',
        'run',
        'build_runner',
        'build',
        '--delete-conflicting-outputs'
      ]);
      progress.finish(showTiming: true);
    }

    progress = logger.progress('Tidying the workspace...');
    await Process.run('dart', ['format', '.']);
    progress.finish(showTiming: true);

    logger.stdout('Your app is ready! 🚀');
  }
}
