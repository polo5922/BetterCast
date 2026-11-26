import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:bettercast_server/bettercast_server.dart';
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

/// Modes:
///   server            API only
///   server --worker   refresh worker only
///   server --all      API + worker in one process (small deployments)
Future<void> main(List<String> args) async {
  final opts = (ArgParser()
        ..addFlag('worker', negatable: false, help: 'Run the refresh worker only')
        ..addFlag('all', negatable: false, help: 'Run API and worker together')
        ..addFlag('migrate', negatable: false, help: 'Apply migrations and exit'))
      .parse(args);

  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((r) {
    stdout.writeln('${r.time.toIso8601String()} ${r.level.name} ${r.loggerName}: '
        '${r.message}${r.error != null ? ' — ${r.error}' : ''}');
  });

  final config = Config.fromEnv();
  final db = Pool.withUrl(config.databaseUrl);
  await _waitForDb(db);
  await runMigrations(db);
  if (opts.flag('migrate')) {
    await db.close();
    return;
  }

  final app = App(db, config);
  final runApi = !opts.flag('worker');
  final runWorker = opts.flag('worker') || opts.flag('all');

  HttpServer? server;
  if (runApi) {
    await app.events.start();
    final handler = const Pipeline()
        .addMiddleware(logRequests(logger: (msg, isError) {
          if (isError || !msg.contains('/health')) Logger('http').info(msg);
        }))
        .addHandler(app.api.handler);
    server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
    server.autoCompress = true;
    Logger('main').info('API listening on :${server.port}');
  }
  if (runWorker) unawaited(app.worker.run());

  await ProcessSignal.sigint.watch().first.catchError((_) => ProcessSignal.sigint);
  Logger('main').info('Shutting down');
  app.worker.stop();
  await server?.close();
  await app.close();
  await db.close();
  exit(0);
}

Future<void> _waitForDb(Pool db) async {
  for (var i = 0;; i++) {
    try {
      await db.execute('SELECT 1');
      return;
    } catch (e) {
      if (i >= 30) rethrow;
      Logger('main').info('Waiting for database... ($e)');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}
